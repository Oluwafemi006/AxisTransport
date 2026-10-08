"""
Vérification des paiements et point d'entrée UNIQUE de l'émission des billets.

Toute émission passe par settle_booking_payment / settle_ticket_payment :
  1. le paiement est vérifié côté serveur (prestataire en ligne) ou attesté par le guichet ;
  2. le montant payé doit être exactement le montant dû ;
  3. la transaction est enregistrée dans PaymentReceipt (unique en base) ;
  4. seulement ensuite, les billets sont émis.
"""
import hashlib
import hmac
import re
import time
import uuid
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

import requests
from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import Booking, PaymentMethod, PaymentReceipt, Ticket, Transaction, User
from .services import pay_and_issue_booking, pay_and_issue_ticket, transition_ticket

FEDAPAY = "FEDAPAY"
KKIAPAY = "KKIAPAY"
SIMULATION = "SIMULATION"
# Moyens de paiement dont la preuve doit être vérifiée par le serveur auprès d'un prestataire.
ONLINE_PROVIDERS = {FEDAPAY, KKIAPAY, SIMULATION}
COUNTER_ROLES = {User.Role.COUNTER, User.Role.ADMIN}

_REFERENCE_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class PaymentNotApproved(ValidationError):
    """Le prestataire connaît la transaction mais elle n'est pas (encore) payée. Porte son statut exact."""

    def __init__(self, message, provider_status):
        super().__init__(message)
        self.provider_status = str(provider_status or "")


@dataclass
class VerifiedPayment:
    provider: str
    external_id: str
    amount: Decimal
    currency: str = ""
    metadata: dict = field(default_factory=dict)


@dataclass
class Settlement:
    target: object
    tickets: list
    transactions: list
    created: bool
    # Paiement reçu après expiration : reçu enregistré, aucun billet émis, remboursement à faire.
    refund_due: bool = False


REFUND_DUE_MESSAGE = (
    "Paiement reçu après l'expiration de la réservation : aucun billet n'a été émis. "
    "Le paiement est enregistré et sera remboursé par Axis."
)


# ─── Vérification auprès des prestataires ────────────────────────────────────

def _fedapay_request(method, path, *, payload=None):
    base_url = (
        "https://api.fedapay.com"
        if settings.FEDAPAY_ENVIRONMENT == "live"
        else "https://sandbox-api.fedapay.com"
    )
    try:
        response = requests.request(
            method,
            f"{base_url}/v1/{path}",
            json=payload,
            headers={"Authorization": f"Bearer {settings.FEDAPAY_SECRET_KEY}", "Accept": "application/json"},
            timeout=15,
        )
    except requests.RequestException as exc:
        raise ValidationError("Impossible de contacter FedaPay.") from exc
    if response.status_code != 200:
        raise ValidationError(f"Requête FedaPay refusée (HTTP {response.status_code}).")
    try:
        data = response.json()
    except ValueError as exc:
        raise ValidationError("Réponse FedaPay illisible.") from exc
    transaction_data = data.get("v1/transaction") if isinstance(data, dict) else None
    if not isinstance(transaction_data, dict):
        raise ValidationError("Réponse FedaPay inattendue.")
    return transaction_data


def _fedapay_fetch_transaction(transaction_id):
    """Relit une transaction auprès de FedaPay, devise incluse. Isolé pour pouvoir être remplacé dans les tests."""
    return _fedapay_request("GET", f"transactions/{transaction_id}?include=currency")


def _fedapay_create_transaction(payload):
    """Crée une transaction FedaPay. Isolé pour pouvoir être remplacé dans les tests."""
    return _fedapay_request("POST", "transactions", payload=payload)


def verify_fedapay_transaction(transaction_id):
    transaction_id = str(transaction_id or "").strip()
    if not settings.FEDAPAY_SECRET_KEY:
        raise ValidationError("Paiement FedaPay indisponible : la clé secrète n'est pas configurée.")
    if not _REFERENCE_PATTERN.match(transaction_id):
        raise ValidationError("Référence de transaction FedaPay invalide.")
    data = _fedapay_fetch_transaction(transaction_id)
    if data.get("status") != "approved":
        raise PaymentNotApproved(
            f"Transaction FedaPay non approuvée (statut : {data.get('status')}).", data.get("status")
        )
    if str(data.get("id", "")) != transaction_id:
        raise ValidationError("La transaction renvoyée par FedaPay ne correspond pas à la référence fournie.")
    try:
        amount = Decimal(str(data.get("amount")))
    except (InvalidOperation, TypeError) as exc:
        raise ValidationError("Montant FedaPay illisible.") from exc
    currency = data.get("currency")
    currency_iso = str(currency.get("iso", "")) if isinstance(currency, dict) else ""
    if currency_iso != "XOF":
        raise ValidationError("La transaction FedaPay n'est pas libellée en XOF.")
    metadata = data.get("custom_metadata")
    return VerifiedPayment(
        provider=FEDAPAY,
        external_id=transaction_id,
        amount=amount,
        currency=currency_iso,
        metadata=metadata if isinstance(metadata, dict) else {},
    )


def verify_kkiapay_transaction(transaction_id):
    """KKiaPay n'est pas implémenté : aucune transaction n'est jamais considérée comme payée."""
    raise ValidationError("Le paiement KKiaPay est désactivé : sa vérification n'est pas implémentée.")


def _simulated_payment(reference, *, target, amount):
    if not (settings.DEBUG and settings.AXIS_PAYMENT_SIMULATION):
        raise ValidationError("Le paiement simulé est désactivé.")
    if not _REFERENCE_PATTERN.match(reference):
        raise ValidationError("Référence de paiement simulé invalide.")
    return VerifiedPayment(
        provider=SIMULATION,
        external_id=reference,
        amount=amount,
        currency=target.currency,
        metadata=_binding_keys(target),
    )


def _verify_online_payment(provider, reference, *, target, amount):
    if provider == FEDAPAY:
        return verify_fedapay_transaction(reference)
    if provider == KKIAPAY:
        return verify_kkiapay_transaction(reference)
    if provider == SIMULATION:
        return _simulated_payment(reference, target=target, amount=amount)
    raise ValidationError("Prestataire de paiement inconnu.")


def _counter_payment(payment_method, *, actor, target):
    """Encaissement attesté par un agent habilité (espèces, etc.)."""
    if not (actor and actor.is_authenticated and actor.role in COUNTER_ROLES):
        raise ValidationError("Ce moyen de paiement ne peut être encaissé qu'au guichet par un agent habilité.")
    return VerifiedPayment(
        provider=payment_method.code.upper(),
        external_id=f"GUICHET-{uuid.uuid4().hex[:16].upper()}",
        amount=amount_due(target, payment_method),
        currency=target.currency,
        metadata=_binding_keys(target),
    )


# ─── Rattachement paiement ↔ réservation ─────────────────────────────────────

def _binding_keys(target):
    if isinstance(target, Booking):
        return {"booking_id": target.pk, "booking_reference": target.reference}
    return {"ticket_id": target.pk, "ticket_reference": target.reference}


def _is_bound_to(proof, target):
    """La transaction doit avoir été créée pour cette réservation précise (métadonnées du prestataire)."""
    return any(
        key in proof.metadata and str(proof.metadata[key]) == str(value)
        for key, value in _binding_keys(target).items()
    )


def payment_quote(target, payment_method):
    """
    Montant à payer, calculé uniquement ici : prix + frais du moyen de paiement
    (fee_percentage, à la charge du client), total arrondi au franc.
    """
    base = target.amount
    total = (base * (Decimal(100) + payment_method.fee_percentage) / Decimal(100)).quantize(
        Decimal("1"), rounding=ROUND_HALF_UP
    )
    return {
        "payment_method": payment_method.pk,
        "code": payment_method.code,
        "label": payment_method.label,
        "amount": base,
        "fee_percentage": payment_method.fee_percentage,
        "fee_amount": total - base,
        "total": total,
        "currency": target.currency,
    }


def amount_due(target, payment_method):
    """Montant exact attendu pour la réservation ou le billet, frais inclus."""
    return payment_quote(target, payment_method)["total"]


def _is_expired(locked):
    expired_statuses = (
        {Booking.Status.EXPIRED, Booking.Status.CANCELLED, Booking.Status.REFUND_DUE}
        if isinstance(locked, Booking)
        else {Ticket.Status.EXPIRED, Ticket.Status.CANCELLED}
    )
    if locked.status in expired_statuses:
        return True
    return bool(
        locked.status == "HELD"
        and locked.reservation_expires_at
        and locked.reservation_expires_at <= timezone.now()
    )


def _mark_refund_due(locked):
    """Libère les sièges encore bloqués et signale la réservation comme payée après expiration."""
    tickets = locked.tickets.all() if isinstance(locked, Booking) else [locked]
    for ticket in tickets:
        if ticket.status == Ticket.Status.HELD:
            transition_ticket(ticket, Ticket.Status.EXPIRED, note="Paiement reçu après expiration : à rembourser")
    if isinstance(locked, Booking):
        locked.status = Booking.Status.REFUND_DUE
        locked.save(update_fields=["status", "updated_at"])
    else:
        locked.refresh_from_db()


# ─── Création de la transaction chez le prestataire ──────────────────────────

def create_checkout(target, *, payment_method):
    """
    Prépare le paiement en ligne d'une réservation ou d'un billet : le montant est fixé ici,
    et la transaction créée chez le prestataire porte l'identifiant de la réservation.
    """
    if not payment_method.active:
        raise ValidationError("Ce moyen de paiement n'est pas actif.")
    provider = payment_method.code.upper()
    if provider not in ONLINE_PROVIDERS:
        raise ValidationError("Ce moyen de paiement ne peut être encaissé qu'au guichet.")
    if not isinstance(target, Booking) and target.booking_id:
        raise ValidationError("Ce billet fait partie d'une réservation : le paiement porte sur la réservation.")
    if target.status != "HELD" or _is_expired(target):
        raise ValidationError("Cette réservation n'est plus en attente de paiement.")
    quote = payment_quote(target, payment_method)

    if provider == SIMULATION:
        if not (settings.DEBUG and settings.AXIS_PAYMENT_SIMULATION):
            raise ValidationError("Le paiement simulé est désactivé.")
        return {"transaction_id": f"SIM-{uuid.uuid4().hex[:16].upper()}", "payment_url": None, "simulated": True, **quote}
    if provider == KKIAPAY:
        verify_kkiapay_transaction(None)
    if not settings.FEDAPAY_SECRET_KEY:
        raise ValidationError("Paiement FedaPay indisponible : la clé secrète n'est pas configurée.")
    if target.currency != "XOF":
        raise ValidationError("FedaPay n'est configuré que pour les paiements en XOF.")
    payload = {
        "description": f"Axis Transport {target.reference}",
        "amount": int(quote["total"]),
        "currency": {"iso": "XOF"},
        "custom_metadata": _binding_keys(target),
    }
    if settings.FEDAPAY_CALLBACK_URL:
        payload["callback_url"] = settings.FEDAPAY_CALLBACK_URL
    data = _fedapay_create_transaction(payload)
    if not data.get("id") or not data.get("payment_url"):
        raise ValidationError("FedaPay n'a pas renvoyé de lien de paiement.")
    return {
        "transaction_id": str(data["id"]),
        "payment_url": data["payment_url"],
        "simulated": False,
        **quote,
    }


# ─── Émission ────────────────────────────────────────────────────────────────

def _existing_settlement(locked, receipt):
    if receipt.refund_due:
        return Settlement(target=locked, tickets=[], transactions=[], created=False, refund_due=True)
    if isinstance(locked, Booking):
        tickets = list(locked.tickets.order_by("created_at"))
    else:
        tickets = [locked]
    transactions = list(
        Transaction.objects.filter(ticket__in=tickets, status=Transaction.Status.SUCCEEDED).order_by("created_at")
    )
    return Settlement(target=locked, tickets=tickets, transactions=transactions, created=False)


def _settle(target, *, payment_method, external_reference, actor, source, proof=None):
    if not payment_method.active:
        raise ValidationError("Ce moyen de paiement n'est pas actif.")
    provider = payment_method.code.upper()
    is_booking = isinstance(target, Booking)
    if not is_booking and target.booking_id:
        raise ValidationError("Ce billet fait partie d'une réservation : le paiement porte sur la réservation.")

    # 1. Preuve de paiement, obtenue AVANT toute écriture et hors verrou.
    if proof is None:
        if provider in ONLINE_PROVIDERS:
            reference = str(external_reference or "").strip()
            if not reference:
                raise ValidationError("Une référence de paiement vérifiable est requise.")
            proof = _verify_online_payment(
                provider, reference, target=target, amount=amount_due(target, payment_method)
            )
        else:
            proof = _counter_payment(payment_method, actor=actor, target=target)
            source = PaymentReceipt.Source.COUNTER
    if proof.provider != provider:
        raise ValidationError("La preuve de paiement ne correspond pas au moyen de paiement choisi.")

    model = Booking if is_booking else Ticket
    target_filter = {"booking": target} if is_booking else {"ticket": target}
    with transaction.atomic():
        locked = model.objects.select_for_update().get(pk=target.pk)

        # 2. Idempotence : la même transaction pour la même réservation ne produit qu'une émission.
        existing = PaymentReceipt.objects.filter(provider=proof.provider, external_id=proof.external_id).first()
        if existing:
            if (existing.booking_id if is_booking else existing.ticket_id) == locked.pk:
                return _existing_settlement(locked, existing)
            raise ValidationError("Cette transaction a déjà été utilisée pour une autre réservation.")

        # 3. Contrôles : rattachement, devise, montant exact.
        if not _is_bound_to(proof, locked):
            raise ValidationError("Cette transaction n'a pas été créée pour cette réservation.")
        if proof.currency != locked.currency:
            raise ValidationError("La devise du paiement ne correspond pas à la réservation.")
        due = amount_due(locked, payment_method)
        if proof.amount != due:
            raise ValidationError(f"Montant payé ({proof.amount}) différent du montant dû ({due}).")
        refund_due = _is_expired(locked)

        # 4. Enregistrement du reçu : les contraintes uniques en base tranchent les accès concurrents.
        try:
            with transaction.atomic():
                receipt = PaymentReceipt.objects.create(
                    provider=proof.provider,
                    external_id=proof.external_id,
                    amount=proof.amount,
                    currency=locked.currency,
                    source=source,
                    recorded_by=actor if actor and actor.is_authenticated else None,
                    refund_due=refund_due,
                    **target_filter,
                )
        except IntegrityError as exc:
            raise ValidationError(
                "Cette transaction a déjà été utilisée ou cette réservation est déjà réglée."
            ) from exc

        # 5. Paiement arrivé après expiration : le reçu est conservé, aucun billet n'est émis.
        if refund_due:
            _mark_refund_due(locked)
            return Settlement(target=locked, tickets=[], transactions=[], created=True, refund_due=True)

        # 6. Émission.
        issuer = actor if actor and actor.is_authenticated else None
        if is_booking:
            locked, tickets, payments = pay_and_issue_booking(
                locked,
                payment_method=payment_method,
                receipt=receipt,
                actor=issuer,
                external_reference=proof.external_id,
            )
        else:
            ticket, payment = pay_and_issue_ticket(
                locked,
                payment_method=payment_method,
                receipt=receipt,
                actor=issuer,
                external_reference=proof.external_id,
            )
            locked, tickets, payments = ticket, [ticket], [payment]
    return Settlement(target=locked, tickets=tickets, transactions=payments, created=True)


def settle_booking_payment(
    booking, *, payment_method, external_reference="", actor=None, source=PaymentReceipt.Source.CLIENT
):
    return _settle(
        booking, payment_method=payment_method, external_reference=external_reference, actor=actor, source=source
    )


def settle_ticket_payment(
    ticket, *, payment_method, external_reference="", actor=None, source=PaymentReceipt.Source.CLIENT
):
    return _settle(
        ticket, payment_method=payment_method, external_reference=external_reference, actor=actor, source=source
    )


# ─── Webhook FedaPay ─────────────────────────────────────────────────────────

def verify_fedapay_signature(payload, header, secret, *, tolerance, now=None):
    """
    Reproduit WebhookSignature::verifyHeader du SDK officiel fedapay-php :
    en-tête « t=<horodatage>,s=<signature> », signature = HMAC-SHA256 hexadécimal
    de « <horodatage>.<corps brut> » avec le secret de l'endpoint.
    """
    if not secret:
        raise ValidationError("Secret de webhook non configuré.")
    timestamp = None
    signatures = []
    for item in str(header or "").split(","):
        key, _, value = item.strip().partition("=")
        if key == "t" and timestamp is None:
            if not value.isdigit():
                raise ValidationError("Horodatage de signature invalide.")
            timestamp = int(value)
        elif key == "s":
            signatures.append(value)
    if timestamp is None or not signatures:
        raise ValidationError("En-tête de signature incomplet.")
    signed_payload = f"{timestamp}.".encode("utf-8") + payload
    expected = hmac.new(secret.encode("utf-8"), signed_payload, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected.encode("utf-8"), s.encode("utf-8")) for s in signatures):
        raise ValidationError("Signature invalide.")
    current = time.time() if now is None else now
    if tolerance > 0 and abs(current - timestamp) > tolerance:
        raise ValidationError("Horodatage de signature hors tolérance.")


def settle_from_fedapay_webhook(transaction_id):
    """Émission déclenchée par un webhook déjà authentifié. La réservation vient des données vérifiées par l'API."""
    proof = verify_fedapay_transaction(transaction_id)
    booking = None
    if "booking_id" in proof.metadata and str(proof.metadata["booking_id"]).isdigit():
        booking = Booking.objects.filter(pk=int(proof.metadata["booking_id"])).first()
    elif "booking_reference" in proof.metadata:
        booking = Booking.objects.filter(reference=str(proof.metadata["booking_reference"])).first()
    if booking is None:
        raise ValidationError("Aucune réservation rattachée à cette transaction.")
    payment_method = PaymentMethod.objects.filter(code__iexact=FEDAPAY, active=True).first()
    if payment_method is None:
        raise ValidationError("Le moyen de paiement FedaPay n'est pas actif.")
    return _settle(
        booking,
        payment_method=payment_method,
        external_reference=proof.external_id,
        actor=None,
        source=PaymentReceipt.Source.WEBHOOK,
        proof=proof,
    )
