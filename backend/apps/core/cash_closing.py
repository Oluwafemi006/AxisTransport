"""Clôture de caisse : période du service, montant attendu, enregistrement non modifiable."""
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone

from .models import CashHandover, Transaction, User
from .payments import ONLINE_PROVIDERS

CLOSING_ROLES = {User.Role.COUNTER, User.Role.CONTROLLER}


def cash_transactions(agent):
    """Espèces : mêmes encaissements que le résumé du jour (réussis, ventes de l'agent, hors Mobile Money)."""
    return (
        Transaction.objects.filter(status=Transaction.Status.SUCCEEDED, ticket__booking__sold_by=agent)
        .exclude(payment_method__code__in=[code.lower() for code in ONLINE_PROVIDERS])
        .exclude(payment_method__code__in=list(ONLINE_PROVIDERS))
    )


def period_start_for(agent):
    """Après la dernière clôture ; pour la première, au premier encaissement en espèces (sinon maintenant)."""
    last = CashHandover.objects.filter(agent=agent, corrects__isnull=True).order_by("-period_end").first()
    if last:
        return last.period_end
    first = cash_transactions(agent).order_by("created_at").values_list("created_at", flat=True).first()
    return first or timezone.now()


def expected_between(agent, start, end):
    total = cash_transactions(agent).filter(created_at__gte=start, created_at__lt=end).aggregate(total=Sum("amount"))["total"]
    return int(total or 0)


def _declared(value):
    try:
        amount = int(str(value).strip())
    except (TypeError, ValueError):
        raise ValidationError("Montant déclaré : un nombre entier de francs CFA.")
    if amount < 0:
        raise ValidationError("Montant déclaré : un nombre entier de francs CFA.")
    return amount


@transaction.atomic
def close_cash(*, agent, declared, received_by, note=""):
    if agent.role not in CLOSING_ROLES:
        raise ValidationError("La clôture concerne un agent du guichet ou un contrôleur.")
    User.objects.select_for_update().get(pk=agent.pk)  # deux clôtures simultanées du même agent : l'une attend
    declared = _declared(declared)
    start, end = period_start_for(agent), timezone.now()
    expected = expected_between(agent, start, end)
    try:
        with transaction.atomic():
            return CashHandover.objects.create(
                agent=agent, period_start=start, period_end=end, expected_fcfa=expected, declared_fcfa=declared,
                difference_fcfa=declared - expected, received_by=received_by, note=str(note or "")[:300],
            )
    except IntegrityError:
        raise ValidationError("Une clôture existe déjà pour cette période.")


@transaction.atomic
def correct_cash(*, original, declared, received_by, note):
    """Correction : nouvelle ligne sur la même période, l'originale reste telle quelle."""
    if original.corrects_id:
        original = original.corrects
    note = str(note or "").strip()
    if not note:
        raise ValidationError("Indiquez le motif de la correction.")
    declared = _declared(declared)
    return CashHandover.objects.create(
        agent=original.agent, period_start=original.period_start, period_end=original.period_end,
        expected_fcfa=original.expected_fcfa, declared_fcfa=declared, difference_fcfa=declared - original.expected_fcfa,
        received_by=received_by, corrects=original, note=note[:300],
    )
