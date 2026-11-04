"""Locations gérées depuis /admin : confirmation, début, fin, annulation et montants, tout est journalisé."""
from django.core.exceptions import ValidationError
from django.db import transaction

from .models import RentalBooking, RentalChange
from .services import parse_fcfa_amount, rental_is_available

S = RentalBooking.Status
RENTAL_TRANSITIONS = {
    S.REQUESTED: {S.CONFIRMED, S.CANCELLED},
    S.CONFIRMED: {S.ACTIVE, S.CANCELLED},
    S.ACTIVE: {S.COMPLETED},
    S.COMPLETED: set(),
    S.CANCELLED: set(),
}


def _fcfa(value):
    return f"{int(value):,} FCFA".replace(",", " ") if value is not None else "—"


@transaction.atomic
def manage_rental(rental, *, actor, status=None, total_amount=None, deposit_amount=None, note=""):
    locked = RentalBooking.objects.select_for_update().select_related("vehicle").get(pk=rental.pk)
    changes = []
    if status and status != locked.status:
        if status not in RENTAL_TRANSITIONS.get(locked.status, set()):
            raise ValidationError(f"Changement impossible : {locked.get_status_display()} → {S(status).label if status in S.values else status}.")
        if status == S.CANCELLED and not note.strip():
            raise ValidationError("Indiquez le motif de l'annulation.")
        if status == S.CONFIRMED and not rental_is_available(locked.vehicle, locked.starts_at, locked.ends_at, exclude_booking=locked):
            raise ValidationError("Ce véhicule est déjà loué sur cette période.")
        changes.append(f"statut {locked.get_status_display()} → {S(status).label}")
        locked.status = status
    for field, value, label in (("total_amount", total_amount, "montant"), ("deposit_amount", deposit_amount, "caution")):
        if value in (None, ""):
            continue
        amount = parse_fcfa_amount(value)
        if getattr(locked, field) is None or int(getattr(locked, field)) != amount:
            changes.append(f"{label} {_fcfa(getattr(locked, field))} → {_fcfa(amount)}")
            setattr(locked, field, amount)
    if not changes:
        return locked, False
    locked.save()
    detail = f"{locked.reference} : {', '.join(changes)}" + (f" (motif : {note.strip()})" if note.strip() else "")
    RentalChange.objects.create(rental=locked, actor=actor, detail=detail[:500])
    return locked, True
