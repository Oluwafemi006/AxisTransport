"""
Encaissement d'un colis par le personnel (agence ou embarquement) : espèces attestées par l'agent,
ou Mobile Money vérifié auprès du prestataire. Un colis est payé quand il a une transaction réussie.
Réutilise la création et la vérification de transaction de payments.py, sans les modifier.
"""
import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from . import payments
from .models import Parcel, ParcelStatusHistory, Transaction, User

STAFF_ROLES = {User.Role.COUNTER, User.Role.CONTROLLER, User.Role.ADMIN}


def is_paid(parcel):
    return parcel.transactions.filter(status=Transaction.Status.SUCCEEDED).exists()


def _check_payable(parcel):
    if parcel.amount is None:
        raise ValidationError("Le prix du colis n'est pas encore fixé par l'agence.")
    if is_paid(parcel):
        raise ValidationError("Ce colis est déjà payé.")


def _note(parcel, actor, text):
    ParcelStatusHistory.objects.create(parcel=parcel, from_status=parcel.status, to_status=parcel.status, changed_by=actor, note=text)


@transaction.atomic
def pay_in_cash(parcel, *, payment_method, actor):
    """L'agent atteste avoir reçu le montant : le colis est payé tout de suite."""
    if actor.role not in STAFF_ROLES:
        raise ValidationError("Seul le personnel peut encaisser un colis.")
    locked = Parcel.objects.select_for_update().get(pk=parcel.pk)
    _check_payable(locked)
    if payment_method.code.upper() in payments.ONLINE_PROVIDERS:
        raise ValidationError("Ce moyen de paiement se règle en ligne, pas en espèces.")
    paid = Transaction.objects.create(
        payment_method=payment_method, amount=locked.amount, currency=locked.currency, parcel=locked,
        status=Transaction.Status.SUCCEEDED, external_reference=f"GUICHET-{uuid.uuid4().hex[:16].upper()}",
    )
    _note(locked, actor, f"Payé en espèces ({payment_method.label})")
    return paid


def start_mobile_money(parcel, *, payment_method, actor):
    """Crée la demande de paiement : la page de paiement s'ouvre pour l'expéditeur."""
    if actor.role not in STAFF_ROLES:
        raise ValidationError("Seul le personnel peut encaisser un colis.")
    if payment_method.code.upper() != payments.FEDAPAY:
        raise ValidationError("Ce moyen de paiement n'est pas un paiement Mobile Money.")
    _check_payable(parcel)
    if not settings.FEDAPAY_SECRET_KEY:
        raise ValidationError("Le paiement Mobile Money n'est pas disponible pour le moment.")
    data = payments._fedapay_create_transaction({
        "description": f"Colis Axis Transport {parcel.tracking_number}",
        "amount": int(parcel.amount),
        "currency": {"iso": "XOF"},
        "custom_metadata": {"parcel_id": parcel.pk, "parcel_reference": parcel.tracking_number},
    })
    if not data.get("id") or not data.get("payment_url"):
        raise ValidationError("Le service Mobile Money n'a pas ouvert de page de paiement. Réessayez.")
    Transaction.objects.create(
        payment_method=payment_method, amount=parcel.amount, currency=parcel.currency, parcel=parcel,
        status=Transaction.Status.PENDING, external_reference=str(data["id"]),
    )
    return {"transaction_id": str(data["id"]), "payment_url": data["payment_url"]}


@transaction.atomic
def verify_mobile_money(parcel, *, actor):
    """Le paiement n'est accepté que s'il est approuvé, au bon montant, et rattaché à ce colis."""
    pending = (
        Transaction.objects.select_for_update()
        .filter(parcel=parcel, status=Transaction.Status.PENDING).order_by("-created_at").first()
    )
    if pending is None:
        if is_paid(parcel):
            return parcel.transactions.filter(status=Transaction.Status.SUCCEEDED).first()
        raise ValidationError("Aucun paiement Mobile Money en attente pour ce colis.")
    proof = payments.verify_fedapay_transaction(pending.external_reference)
    if str(proof.metadata.get("parcel_id")) != str(parcel.pk):
        raise ValidationError("Le paiement reçu ne correspond pas à ce colis.")
    if proof.amount != parcel.amount or proof.currency != parcel.currency:
        raise ValidationError("Le montant payé ne correspond pas au prix du colis.")
    pending.status = Transaction.Status.SUCCEEDED
    pending.save(update_fields=["status", "updated_at"])
    _note(parcel, actor, "Payé par Mobile Money")
    return pending


def receipt(parcel):
    """Contenu du ticket colis : ce que l'agence imprime ou remet en PDF."""
    paid = parcel.transactions.filter(status=Transaction.Status.SUCCEEDED).select_related("payment_method").first()
    return {
        "title": "Ticket colis",
        "tracking_number": parcel.tracking_number,
        "origin": parcel.origin.name,
        "destination": parcel.destination.name,
        "sender_name": parcel.sender_name,
        "sender_phone": parcel.sender_phone,
        "recipient_name": parcel.recipient_name,
        "recipient_phone": parcel.recipient_phone,
        "description": parcel.description,
        "amount": int(parcel.amount) if parcel.amount is not None else None,
        "currency": parcel.currency,
        "paid": paid is not None,
        "payment_mode": paid.payment_method.label if paid else "",
        "paid_at": timezone.localtime(paid.updated_at).isoformat() if paid else None,
        "departure_at": timezone.localtime(parcel.trip.departure_at).isoformat() if parcel.trip_id else None,
        "created_at": timezone.localtime(parcel.created_at).isoformat(),
        "status_display": parcel.get_status_display(),
    }
