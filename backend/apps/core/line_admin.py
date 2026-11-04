"""Villes, ordre des arrêts de la ligne et tarifs par tronçon, modifiés depuis /admin (tout est journalisé)."""
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .axis import RETIRED_POSITION_OFFSET, axis_routes, set_line_stops, set_route_stops
from .models import LineChange, LineStop, Location, SegmentFare, SegmentFareChange, Ticket
from .services import parse_fcfa_amount

# Billets encore à voyager : un arrêt qui en porte ne peut pas sortir de la ligne.
_LIVE_TICKET_STATUSES = [Ticket.Status.HELD, Ticket.Status.PAID, Ticket.Status.ISSUED]


def log_line_change(actor, detail):
    LineChange.objects.create(actor=actor, detail=detail[:500])


def line_payload():
    """Arrêts de la ligne dans l'ordre (aller), et villes actives hors ligne qu'on peut y ajouter."""
    stops = list(
        LineStop.objects.filter(position__lte=RETIRED_POSITION_OFFSET).select_related("location").order_by("position")
    )
    on_line = {stop.location_id for stop in stops}
    others = Location.objects.filter(active=True).exclude(pk__in=on_line).order_by("name")
    return {
        "stops": [
            {"location_id": stop.location_id, "name": stop.location.name, "position": stop.position,
             "active": stop.location.active}
            for stop in stops
        ],
        "available": [{"location_id": place.pk, "name": place.name} for place in others],
    }


@transaction.atomic
def save_line(location_ids, *, actor):
    """
    Nouvel ordre des arrêts (sens aller) ; les deux parcours terminus ↔ terminus suivent cet ordre.
    Refusé si un arrêt retiré porte encore des billets à voyager.
    """
    if not isinstance(location_ids, list) or not all(isinstance(pk, int) for pk in location_ids):
        raise ValidationError("Indiquez la liste ordonnée des villes de la ligne.")
    if len(set(location_ids)) != len(location_ids):
        raise ValidationError("Une ville ne peut apparaître qu'une fois sur la ligne.")
    if len(location_ids) < 2:
        raise ValidationError("La ligne doit compter au moins deux villes.")
    places = {place.pk: place for place in Location.objects.filter(pk__in=location_ids)}
    if len(places) != len(location_ids):
        raise ValidationError("Ville inconnue.")
    inactive = [places[pk].name for pk in location_ids if not places[pk].active]
    if inactive:
        raise ValidationError(f"Ville désactivée : {', '.join(inactive)}. Réactivez-la avant de l'ajouter à la ligne.")
    names = [places[pk].name for pk in location_ids]
    before = [stop.location.name for stop in LineStop.objects.filter(position__lte=RETIRED_POSITION_OFFSET)
              .select_related("location").order_by("position")]
    if before == names:
        return line_payload(), False

    # Les terminus portent les parcours : les changer créerait d'autres parcours, hors de ce lot.
    forward, backward = axis_routes()
    if names[0] != forward.origin.name or names[-1] != forward.destination.name:
        raise ValidationError(
            f"La ligne doit commencer par {forward.origin.name} et finir par {forward.destination.name}."
        )
    removed = [name for name in before if name not in names]
    if removed:
        busy = Ticket.objects.filter(
            Q(origin__name__in=removed) | Q(destination__name__in=removed),
            status__in=_LIVE_TICKET_STATUSES,
            trip__departure_at__gte=timezone.now(),
        )
        if busy.exists():
            raise ValidationError(
                f"Impossible de retirer {', '.join(removed)} : des billets à venir montent ou descendent à cet arrêt."
            )
    set_line_stops(names)
    # Un arrêt retiré n'est plus desservi : ses tarifs sont retirés aussi (journalisés, rétablissables).
    for fare in SegmentFare.objects.filter(
        Q(start__location__name__in=removed) | Q(end__location__name__in=removed), active=True
    ):
        set_segment_fare_active(fare, False, actor=actor)
    set_route_stops(forward, names)
    set_route_stops(backward, names[::-1])
    log_line_change(actor, f"Ordre de la ligne : {' → '.join(before) or '—'} devient {' → '.join(names)}")
    return line_payload(), True


@transaction.atomic
def create_segment_fare(origin_id, destination_id, amount, *, actor):
    """Tarif d'un tronçon entre deux arrêts de la ligne ; un tarif retiré est rétabli au nouveau prix."""
    amount = parse_fcfa_amount(amount)
    stops = {
        stop.location_id: stop
        for stop in LineStop.objects.filter(
            location_id__in=[origin_id, destination_id], position__lte=RETIRED_POSITION_OFFSET
        ).select_related("location")
    }
    if origin_id == destination_id or len(stops) != 2:
        raise ValidationError("Choisissez deux villes différentes de la ligne.")
    first, second = sorted(stops.values(), key=lambda stop: stop.position)
    fare = SegmentFare.objects.select_for_update().filter(start=first, end=second).first()
    if fare is not None and fare.active:
        raise ValidationError(f"{fare.label} a déjà un tarif : modifiez son prix dans la grille.")
    if fare is None:
        fare = SegmentFare.objects.create(start=first, end=second, amount=amount, currency="XOF", updated_by=actor)
        SegmentFareChange.objects.create(fare=fare, changed_by=actor, old_amount=None, new_amount=amount,
                                         note="Tarif créé")
    else:
        old = fare.amount
        fare.amount, fare.active, fare.updated_by = amount, True, actor
        fare.save(update_fields=["amount", "active", "updated_by", "updated_at"])
        SegmentFareChange.objects.create(fare=fare, changed_by=actor, old_amount=old, new_amount=amount,
                                         note="Tarif rétabli")
    return fare


@transaction.atomic
def set_segment_fare_active(fare, active, *, actor):
    """Retire ou rétablit un tarif : un tarif retiré rend le tronçon non vendable ; rien n'est effacé."""
    locked = SegmentFare.objects.select_for_update().get(pk=fare.pk)
    if locked.active == active:
        return locked, False
    locked.active, locked.updated_by = active, actor
    locked.save(update_fields=["active", "updated_by", "updated_at"])
    SegmentFareChange.objects.create(
        fare=locked, changed_by=actor, old_amount=locked.amount, new_amount=locked.amount,
        note="Tarif rétabli" if active else "Tarif retiré",
    )
    return locked, True
