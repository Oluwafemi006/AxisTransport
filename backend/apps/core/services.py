import re
import hashlib
import secrets
from datetime import datetime, timedelta
from types import SimpleNamespace
from decimal import ROUND_HALF_UP, Decimal

from django.core.exceptions import ImproperlyConfigured, ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import (
    BoardingPoint,
    Booking,
    FareRule,
    FeatureFlag,
    Parcel,
    ParcelStatusHistory,
    PaymentMethod,
    PaymentReceipt,
    Passenger,
    RentalBooking,
    Seat,
    SystemSetting,
    Ticket,
    TicketControl,
    TicketStatusHistory,
    Transaction,
    Route,
    Trip,
    PaymentAttempt,
    LineStop,
    Location,
    SegmentFare,
    SegmentFareChange,
    Tax,
    Vehicle,
    WeeklySchedule,
)


TICKET_TRANSITIONS = {
    Ticket.Status.HELD: {Ticket.Status.PAID, Ticket.Status.CANCELLED, Ticket.Status.EXPIRED},
    Ticket.Status.PAID: {Ticket.Status.ISSUED, Ticket.Status.CANCELLED, Ticket.Status.REFUNDED},
    Ticket.Status.ISSUED: {Ticket.Status.CHECKED, Ticket.Status.CANCELLED, Ticket.Status.REFUNDED},
    Ticket.Status.CHECKED: {Ticket.Status.COMPLETED},
    Ticket.Status.COMPLETED: set(),
    Ticket.Status.CANCELLED: set(),
    Ticket.Status.REFUNDED: set(),
    Ticket.Status.EXPIRED: {Ticket.Status.HELD, Ticket.Status.PAID},
}

AUTO_SEAT_NOTE = "Attribution automatique du siège"
SEAT_JUST_TAKEN_MESSAGE = "Cette place vient d'être prise"

PARCEL_TRANSITIONS = {
    Parcel.Status.REGISTERED: {Parcel.Status.DEPOSITED},
    Parcel.Status.DEPOSITED: {Parcel.Status.ACCEPTED},
    Parcel.Status.ACCEPTED: {Parcel.Status.ASSIGNED},
    Parcel.Status.ASSIGNED: {Parcel.Status.LOADED},
    Parcel.Status.LOADED: {Parcel.Status.IN_TRANSIT},
    Parcel.Status.IN_TRANSIT: {Parcel.Status.ARRIVED},
    Parcel.Status.ARRIVED: {Parcel.Status.READY_FOR_PICKUP},
    Parcel.Status.READY_FOR_PICKUP: {Parcel.Status.PICKED_UP},
    Parcel.Status.PICKED_UP: set(),
}


def feature_enabled(key):
    return FeatureFlag.objects.filter(key=key, enabled=True).exists()


class ReservationsClosed(ImproperlyConfigured):
    """
    Durée de blocage d'un siège (« ticket_hold_minutes ») absente ou invalide : aucune réservation possible.
    Deux messages sans texte technique : un pour le client, un pour le personnel (qui sait quoi faire).
    """

    CLIENT_MESSAGE = "Les réservations ne sont pas encore ouvertes. Réessayez plus tard ou contactez l'agence."
    STAFF_MESSAGE = (
        "Vente impossible : la durée de blocage d'un siège n'est pas encore saisie. "
        "Un administrateur doit la renseigner dans le portail /admin, onglet « Tarifs & règles »."
    )

    def __init__(self):
        super().__init__(self.CLIENT_MESSAGE)


def configured_hold_duration():
    try:
        raw_value = SystemSetting.objects.get(key="ticket_hold_minutes").value
        minutes = int(raw_value)
    except (SystemSetting.DoesNotExist, TypeError, ValueError) as exc:
        raise ReservationsClosed() from exc
    if minutes <= 0:
        raise ReservationsClosed()
    return timedelta(minutes=minutes)


def is_plausible_phone(value):
    """Forme générale d'un numéro de téléphone, sans règle propre à un pays : 6 à 15 chiffres, « + » initial admis."""
    text = (value or "").strip()
    if not re.fullmatch(r"\+?[0-9(][0-9 ().-]*", text):
        return False
    return 6 <= sum(character.isdigit() for character in text) <= 15


DEFAULT_BOARDING_LEAD_MINUTES = 30


def boarding_lead_minutes():
    """Avance de l'embarquement sur le départ (réglage admin 'boarding_lead_minutes', 30 par défaut)."""
    try:
        minutes = int(SystemSetting.objects.get(key="boarding_lead_minutes").value)
    except (SystemSetting.DoesNotExist, TypeError, ValueError):
        return DEFAULT_BOARDING_LEAD_MINUTES
    return minutes if minutes >= 0 else DEFAULT_BOARDING_LEAD_MINUTES


def boarding_time(trip, lead_minutes=None):
    """Heure d'embarquement à l'origine du trajet : départ moins l'avance réglée. Calculée, jamais stockée."""
    if not trip or not trip.departure_at:
        return None
    if lead_minutes is None:
        lead_minutes = boarding_lead_minutes()
    return trip.departure_at - timedelta(minutes=lead_minutes)


PLANNING_MAX_DAYS = 90  # proposition : au-delà, générer en plusieurs fois


@transaction.atomic
def generate_alternating_trips(*, route, vehicle, start_date, days, departure_time):
    """
    Planning quotidien en sens alterné : un départ par jour à `departure_time` (heure du Bénin), le premier
    jour sur `route`, le lendemain sur le parcours inverse, et ainsi de suite (le sens suit le rang du jour).
    Ne crée rien un jour où ce véhicule a déjà un départ (non annulé), ni un départ déjà passé ;
    ne modifie aucun départ existant. Heure d'arrivée laissée vide. Renvoie (créés, jours ignorés).
    """
    if not 1 <= days <= PLANNING_MAX_DAYS:
        raise ValidationError(f"Le nombre de jours doit être compris entre 1 et {PLANNING_MAX_DAYS}.")
    if start_date < timezone.localdate():
        raise ValidationError("La date de début ne peut pas être passée.")
    if not vehicle.seat_labels:
        raise ValidationError("Saisissez d'abord la capacité ou le plan de sièges de ce véhicule (onglet Flotte).")
    reverse = Route.objects.filter(origin=route.destination, destination=route.origin).first()
    if reverse is None:
        raise ValidationError(f"Le parcours inverse de « {route} » n'existe pas : impossible d'alterner.")
    if not (route.active and reverse.active):
        raise ValidationError("Les deux parcours doivent être actifs.")

    created, skipped = [], []
    for index in range(days):
        day = start_date + timedelta(days=index)
        day_route = route if index % 2 == 0 else reverse
        departure = timezone.make_aware(datetime.combine(day, departure_time))
        if departure <= timezone.now():
            skipped.append({"date": day.isoformat(), "reason": "heure déjà passée"})
            continue
        if (
            Trip.objects.filter(vehicle=vehicle, departure_at__date=day)
            .exclude(status=Trip.Status.CANCELLED)
            .exists()
        ):
            skipped.append({"date": day.isoformat(), "reason": "ce véhicule a déjà un départ ce jour-là"})
            continue
        trip = Trip.objects.create(route=day_route, vehicle=vehicle, departure_at=departure)
        generate_trip_seats(trip)
        created.append(trip)
    return created, skipped


@transaction.atomic
def generate_trips_from_schedule(*, start_date=None, weeks=4, vehicle_override=None):
    """
    Génère les trajets réels (Trip) pour les semaines à venir à partir des entrées actives de WeeklySchedule.
    - Évite les doublons : ne crée rien si un départ identique existe déjà.
    - Ne crée rien pour les dates/heures passées.
    - Génère les sièges si le véhicule a une capacité configurée.
    """
    if start_date is None:
        start_date = timezone.localdate()

    total_days = max(1, min(weeks, 12)) * 7
    schedules = list(
        WeeklySchedule.objects.filter(is_active=True)
        .exclude(route__isnull=True)
        .exclude(departure_time__isnull=True)
        .select_related("route", "vehicle")
    )
    if not schedules:
        return []

    fallback_bus = Vehicle.objects.filter(category=Vehicle.Category.BUS, state=Vehicle.State.ACTIVE).first()
    created_trips = []

    for day_offset in range(total_days):
        current_date = start_date + timedelta(days=day_offset)
        day_of_week = current_date.weekday()
        matching_schedules = [s for s in schedules if s.day_of_week == day_of_week]

        for schedule in matching_schedules:
            departure_at = timezone.make_aware(datetime.combine(current_date, schedule.departure_time))
            if departure_at <= timezone.now():
                continue

            vehicle = schedule.vehicle or vehicle_override or fallback_bus
            if not vehicle:
                continue

            already_exists = (
                Trip.objects.filter(
                    route=schedule.route,
                    departure_at=departure_at,
                )
                .exclude(status=Trip.Status.CANCELLED)
                .exists()
            )
            if already_exists:
                continue

            # Si ce véhicule a déjà un autre départ ce jour-là à la même heure
            vehicle_conflict = (
                Trip.objects.filter(
                    vehicle=vehicle,
                    departure_at=departure_at,
                )
                .exclude(status=Trip.Status.CANCELLED)
                .exists()
            )
            if vehicle_conflict:
                continue

            trip = Trip.objects.create(
                route=schedule.route,
                vehicle=vehicle,
                departure_at=departure_at,
                status=Trip.Status.SCHEDULED,
                note=schedule.notes or "Généré selon planning hebdomadaire",
            )
            if vehicle.seat_labels:
                generate_trip_seats(trip)
            created_trips.append(trip)

    return created_trips


def generate_trip_seats(trip):
    labels = trip.vehicle.seat_labels
    if not labels:
        raise ValidationError("La capacité ou le plan de sièges du véhicule doit être configuré avant le trajet.")
    layout = {
        str(item.get("label")): item
        for item in (trip.vehicle.seat_configuration or [])
        if isinstance(item, dict) and item.get("label")
    }
    seats = []
    for label in labels:
        item = layout.get(str(label), {})
        seat, _ = Seat.objects.get_or_create(
            trip=trip,
            number=str(label),
            defaults={
                "row": item.get("row"),
                "column": item.get("column"),
                "allowed_passenger_types": item.get("allowed_passenger_types", []),
            },
        )
        seats.append(seat)
    return seats


def resolve_fare(trip, at=None):
    at = at or timezone.now()
    rules = FareRule.objects.filter(route=trip.route, active=True).filter(
        Q(valid_from__isnull=True) | Q(valid_from__lte=at),
        Q(valid_until__isnull=True) | Q(valid_until__gte=at),
    )
    temporal_enabled = feature_enabled(FeatureFlag.Key.TEMPORAL_PRICING)
    if temporal_enabled:
        remaining = trip.departure_at - at
        for rule in rules:
            if rule.rule_type == FareRule.RuleType.PROMOTION:
                return rule
            if rule.rule_type == FareRule.RuleType.ADVANCE and remaining >= timedelta(days=rule.advance_days or 0):
                return rule
            if rule.rule_type == FareRule.RuleType.SAME_DAY and timezone.localdate(at) == timezone.localdate(
                trip.departure_at
            ):
                return rule
    standard = rules.filter(rule_type=FareRule.RuleType.STANDARD).first()
    if not standard:
        raise ImproperlyConfigured(f"Aucun tarif standard actif n'est configuré pour le trajet {trip.route}.")
    return standard


def resolve_location(identifier):
    """Résout une Location par son ID ou par son nom (insensible à la casse)."""
    if isinstance(identifier, Location):
        return identifier
    if not identifier:
        return None
    val_str = str(identifier).strip()
    if val_str.isdigit():
        loc = Location.objects.filter(pk=int(val_str)).first()
        if loc:
            return loc
    return Location.objects.filter(name__iexact=val_str).first()


def find_trips_for_waypoint_direction(queryset, origin=None, destination=None):
    """
    Filtre un queryset de Trip selon la direction des escales.
    - Si origin et destination sont fournis :
      Vérifie que les deux villes existent sur l'itinéraire du bus prévu
      et que l'index de départ est strictement inférieur à l'index d'arrivée
      dans le sens de circulation de ce bus spécifique.
    - Si seulement origin est fourni :
      Vérifie que le bus dessert origin et n'est pas à son terminus.
    - Si seulement destination est fourni :
      Vérifie que le bus dessert destination et n'est pas à son départ.
    """
    origin_loc = resolve_location(origin) if origin else None
    dest_loc = resolve_location(destination) if destination else None

    if origin and not origin_loc:
        return queryset.none()
    if destination and not dest_loc:
        return queryset.none()

    if origin_loc and dest_loc:
        if origin_loc.pk == dest_loc.pk:
            return queryset.none()
        valid_route_ids = [
            route.pk
            for route in Route.objects.filter(active=True).prefetch_related("stops__location")
            if route.has_waypoint_direction(origin_loc, dest_loc)
        ]
        return queryset.filter(route_id__in=valid_route_ids)

    if origin_loc:
        valid_route_ids = [
            route.pk
            for route in Route.objects.filter(active=True).prefetch_related("stops__location")
            if route.can_board_at(origin_loc)
        ]
        return queryset.filter(route_id__in=valid_route_ids)

    if dest_loc:
        valid_route_ids = [
            route.pk
            for route in Route.objects.filter(active=True).prefetch_related("stops__location")
            if route.can_alight_at(dest_loc)
        ]
        return queryset.filter(route_id__in=valid_route_ids)

    return queryset


def _segment_bounds(origin, destination):
    """Les deux arrêts de la ligne correspondant à deux lieux, rangés dans l'ordre de la ligne."""
    stops = {stop.location_id: stop for stop in LineStop.objects.filter(location__in=[origin, destination])}
    if origin == destination or len(stops) != 2:
        return None
    first, second = stops[origin.pk], stops[destination.pk]
    return (first, second) if first.position < second.position else (second, first)


def resolve_segment_fare(origin, destination):
    """
    Prix du tronçon entre deux lieux, identique dans les deux sens.
    Aucun tarif enregistré : le tronçon n'est pas vendable, sans prix de repli.
    """
    bounds = _segment_bounds(origin, destination)
    fare = SegmentFare.objects.filter(start=bounds[0], end=bounds[1]).first() if bounds else None
    if fare is None:
        raise ImproperlyConfigured(f"Aucun prix n'est défini entre {origin} et {destination} : tronçon non vendable.")
    return fare


def trip_fare(trip):
    """
    Prix du billet pour un départ : celui du tronçon de la grille entre le départ et l'arrivée du parcours
    (trajet complet). La règle tarifaire du parcours (resolve_fare) ne fixe plus le prix ; son code est gardé.
    Pas de prix dans la grille : départ non vendable (ImproperlyConfigured), sans prix de repli.
    """
    fare = resolve_segment_fare(trip.route.origin, trip.route.destination)
    return SimpleNamespace(id=fare.id, name=fare.label, amount=Decimal(fare.amount), currency=fare.currency)


def tax_breakdown(price, taxes=None):
    """
    Décompose un prix TTC (taxes comprises, rien ne s'ajoute) : HT = TTC / (1 + taux), taxe = TTC - HT,
    arrondis au franc ; HT + taxes vaut toujours exactement le TTC.
    Plusieurs taxes incluses : leur part est répartie au prorata des taux, la dernière reçoit le reste.
    Renvoie (HT, [{"name", "rate", "amount"}]). Sans taxe incluse active : HT = TTC, aucune ligne.
    """
    price = Decimal(price).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    if taxes is None:
        taxes = list(Tax.objects.filter(active=True, included=True).order_by("name", "pk"))
    taxes = [tax for tax in taxes if Decimal(tax.rate) > 0]
    if not taxes:
        return price, []
    total_rate = sum(Decimal(tax.rate) for tax in taxes)
    excl = (price * Decimal(100) / (Decimal(100) + total_rate)).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    total_tax = price - excl
    lines, assigned = [], Decimal(0)
    for index, tax in enumerate(taxes):
        if index == len(taxes) - 1:
            amount = total_tax - assigned
        else:
            amount = (total_tax * Decimal(tax.rate) / total_rate).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
        assigned += amount
        lines.append({"name": tax.name, "rate": str(Decimal(tax.rate).normalize()), "amount": int(amount)})
    return excl, lines


def _tax_snapshot(price):
    excl, lines = tax_breakdown(price)
    return {"price_excl_tax": excl, "tax_lines": lines}


def clean_buyer_ifu(value):
    """IFU de l'acheteur, facultatif : texte court sans mise en forme imposée (format officiel non vérifié ici)."""
    text = " ".join(str(value or "").split())
    if len(text) > 30:
        raise ValidationError("L'IFU de l'acheteur ne doit pas dépasser 30 caractères.")
    if text and not re.fullmatch(r"[A-Za-z0-9 ./-]+", text):
        raise ValidationError("L'IFU de l'acheteur ne peut contenir que des lettres, des chiffres, des espaces, « . », « / » ou « - ».")
    return text


def parse_fcfa_amount(value):
    """Prix saisi par l'administrateur : nombre entier de francs CFA, strictement positif."""
    text = str(value).strip().replace(" ", "").replace("\u202f", "").replace("\xa0", "") if value is not None else ""
    if isinstance(value, bool) or not text.isdigit():
        raise ValidationError("Le prix doit être un nombre entier de francs CFA, sans virgule ni lettre.")
    amount = int(text)
    if amount <= 0:
        raise ValidationError("Le prix doit être supérieur à zéro.")
    if amount > 2_147_483_647:
        raise ValidationError("Ce prix est trop grand pour être enregistré.")
    return amount


@transaction.atomic
def update_segment_fare(fare, amount, *, actor):
    """Change le prix d'un tronçon et l'inscrit au journal. Même prix : rien n'est modifié ni journalisé."""
    amount = parse_fcfa_amount(amount)
    locked = SegmentFare.objects.select_for_update().get(pk=fare.pk)
    if locked.amount == amount:
        return locked, False
    old = locked.amount
    locked.amount = amount
    locked.updated_by = actor
    locked.save(update_fields=["amount", "updated_by", "updated_at"])
    SegmentFareChange.objects.create(fare=locked, changed_by=actor, old_amount=old, new_amount=amount)
    return locked, True


def release_expired_holds(at=None):
    at = at or timezone.now()
    with transaction.atomic():
        tickets = list(
            Ticket.objects.select_for_update()
            .select_related("seat")
            .filter(status=Ticket.Status.HELD, reservation_expires_at__lte=at)
        )
        booking_ids = {ticket.booking_id for ticket in tickets if ticket.booking_id}
        for ticket in tickets:
            ticket.status = Ticket.Status.EXPIRED
            ticket.save(update_fields=["status", "updated_at"])
            TicketStatusHistory.objects.create(
                ticket=ticket,
                from_status=Ticket.Status.HELD,
                to_status=Ticket.Status.EXPIRED,
                note="Expiration automatique de la réservation temporaire",
            )
            ticket.seat.status = Seat.Status.AVAILABLE
            ticket.seat.hold_expires_at = None
            ticket.seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
        for booking_id in booking_ids:
            if not Ticket.objects.filter(booking_id=booking_id, status=Ticket.Status.HELD).exists():
                Booking.objects.filter(pk=booking_id, status=Booking.Status.HELD).update(
                    status=Booking.Status.EXPIRED, updated_at=at
                )
    return len(tickets)


@transaction.atomic
def cancel_held_booking(booking, *, actor=None):
    """
    Annulation par le client d'une réservation NON payée : les sièges sont libérés immédiatement.
    Renvoie (réservation, annulée_maintenant). Déjà annulée ou déjà expirée : sans effet (idempotent).
    Une réservation payée ne s'annule pas par cette voie.
    """
    locked = Booking.objects.select_for_update().get(pk=booking.pk)
    if locked.status in {Booking.Status.CANCELLED, Booking.Status.EXPIRED}:
        return locked, False
    if locked.status != Booking.Status.HELD:
        raise ValidationError("Cette réservation est déjà payée : elle ne peut pas être annulée ici.")
    for ticket in locked.tickets.filter(status=Ticket.Status.HELD):
        transition_ticket(ticket, Ticket.Status.CANCELLED, actor=actor, note="Annulée par le client avant paiement")
    locked.status = Booking.Status.CANCELLED
    locked.save(update_fields=["status", "updated_at"])
    # Transactions déjà créées chez le prestataire : abandonnées côté Axis. Si le client paie quand même,
    # le paiement suit le chemin « à rembourser » (aucun billet, aucun siège repris).
    PaymentAttempt.objects.filter(booking=locked, outcome=PaymentAttempt.Outcome.PENDING).update(
        outcome=PaymentAttempt.Outcome.CANCELLED, updated_at=timezone.now()
    )
    return locked, True


def hash_guest_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


DEPARTED_MESSAGE = "Ce départ est déjà parti : il n'est plus possible de réserver."


def _seat_numeric_order(seat):
    text = str(seat.number or "").strip()
    if text.isdigit():
        return int(text)
    match = re.search(r"\d+", text)
    return int(match.group(0)) if match else 999999


def _seat_effective_coords(seat):
    """
    Retourne (row, col, side_block, numeric_num, label) pour regrouper les places côte à côte.
    Sur un car 2+2 (Yutong), les colonnes 1-2 sont à gauche du couloir (bloc 0) et 3-4 à droite (bloc 1).
    """
    num = _seat_numeric_order(seat)
    if seat.row is not None and seat.column is not None:
        row, col = int(seat.row), int(seat.column)
    elif 1 <= num < 999999:
        row = (num - 1) // 4 + 1
        col = (num - 1) % 4 + 1
    else:
        row, col = 999, 999
    side_block = 0 if col <= 2 else 1
    return row, col, side_block, num, str(seat.number)


def _seat_allows_passenger(seat, passenger_type):
    allowed = seat.allowed_passenger_types or []
    return not allowed or passenger_type in allowed


def select_automatic_seats(available_seats, passenger_types):
    """
    Retient automatiquement `len(passenger_types)` places parmi `available_seats` :
    - groupées côte à côte si possible (même duo gauche/droite d'une rangée, ou même rangée),
    - sinon par plus petit numéro de siège.
    """
    count = len(passenger_types)
    if count == 0:
        return []
    pool = sorted(
        list(available_seats),
        key=lambda s: (
            _seat_numeric_order(s),
            _seat_effective_coords(s)[0],
            _seat_effective_coords(s)[1],
            str(s.number),
        ),
    )
    if len(pool) < count:
        raise ValidationError("Il n'y a plus assez de places libres sur ce départ.")

    has_restrictions = any(bool(s.allowed_passenger_types) for s in pool)
    if not has_restrictions and count >= 2:
        by_row = {}
        by_pair = {}
        for s in pool:
            row, _col, side_block, _, _ = _seat_effective_coords(s)
            by_row.setdefault(row, []).append(s)
            by_pair.setdefault((row, side_block), []).append(s)

        if count == 2:
            for (_row, _side), seats_in_pair in sorted(by_pair.items()):
                if len(seats_in_pair) >= 2:
                    return seats_in_pair[:2]
            for _row, seats_in_row in sorted(by_row.items()):
                if len(seats_in_row) >= 2:
                    return seats_in_row[:2]
        else:
            for _row, seats_in_row in sorted(by_row.items()):
                if len(seats_in_row) >= count:
                    return seats_in_row[:count]
            chosen = []
            used_ids = set()
            for (_row, _side), seats_in_pair in sorted(by_pair.items()):
                while len(seats_in_pair) >= 2 and (count - len(chosen)) >= 2:
                    pair = [s for s in seats_in_pair if s.pk not in used_ids][:2]
                    if len(pair) < 2:
                        break
                    chosen.extend(pair)
                    used_ids.update(s.pk for s in pair)
                    seats_in_pair = [s for s in seats_in_pair if s.pk not in used_ids]
            for s in pool:
                if len(chosen) >= count:
                    break
                if s.pk not in used_ids:
                    chosen.append(s)
                    used_ids.add(s.pk)
            if len(chosen) == count:
                return chosen

    chosen = []
    used_ids = set()
    for p_type in passenger_types:
        matched = next(
            (s for s in pool if s.pk not in used_ids and _seat_allows_passenger(s, p_type)),
            None,
        )
        if matched is None:
            raise ValidationError("Aucun siège libre ne correspond au type de passager demandé.")
        chosen.append(matched)
        used_ids.add(matched.pk)
    return chosen


def recover_expired_booking_seats(locked_booking):
    """
    Paiement confirmé après expiration de la retenue (pour une réservation non annulée) :
    1. Si les places initialement retenues sont toujours libres, les reprendre ;
    2. Sinon, attribuer d'autres places libres du même voyage (côte à côte si possible, sinon plus petit numéro) ;
    3. S'il n'y a plus assez de places libres sur le voyage, renvoyer False (la réservation sera marquée REFUND_DUE).
    """
    if locked_booking.status in {Booking.Status.CANCELLED, Booking.Status.REFUND_DUE}:
        return False

    now = timezone.now()
    # Libérer d'abord les retenues expirées d'autres réservations sur ce voyage
    stale_other_tickets = list(
        Ticket.objects.select_for_update()
        .select_related("seat")
        .filter(
            trip_id=locked_booking.trip_id,
            status=Ticket.Status.HELD,
            reservation_expires_at__lte=now,
        )
        .exclude(booking_id=locked_booking.pk)
    )
    stale_booking_ids = {t.booking_id for t in stale_other_tickets if t.booking_id}
    for stale in stale_other_tickets:
        stale.status = Ticket.Status.EXPIRED
        stale.save(update_fields=["status", "updated_at"])
        TicketStatusHistory.objects.create(
            ticket=stale,
            from_status=Ticket.Status.HELD,
            to_status=Ticket.Status.EXPIRED,
            note="Expiration automatique de la réservation temporaire",
        )
        stale.seat.status = Seat.Status.AVAILABLE
        stale.seat.hold_expires_at = None
        stale.seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
    for b_id in stale_booking_ids:
        if not Ticket.objects.filter(booking_id=b_id, status=Ticket.Status.HELD).exists():
            Booking.objects.filter(pk=b_id, status=Booking.Status.HELD).update(
                status=Booking.Status.EXPIRED, updated_at=now
            )

    locked_trip = Trip.objects.select_for_update().get(pk=locked_booking.trip_id)
    if locked_trip.status not in {Trip.Status.SCHEDULED, Trip.Status.BOARDING}:
        return False

    all_seats = list(Seat.objects.select_for_update().filter(trip=locked_trip))
    seats_by_pk = {s.pk: s for s in all_seats}
    tickets = list(
        locked_booking.tickets.select_for_update(of=("self",))
        .select_related("seat", "passenger")
        .order_by("created_at")
    )
    if not tickets:
        return False

    reclaimed = {}
    reclaimed_seat_ids = set()
    needs_reassignment = []

    for ticket in tickets:
        orig_seat = seats_by_pk.get(ticket.seat_id)
        # Le siège d'origine est disponible s'il est AVAILABLE, ou s'il est encore HELD par ce billet lui-même
        still_held_by_this_ticket = (
            orig_seat is not None
            and orig_seat.status == Seat.Status.HELD
            and ticket.status == Ticket.Status.HELD
            and not Ticket.objects.filter(seat=orig_seat, status=Ticket.Status.HELD).exclude(pk=ticket.pk).exists()
        )
        if orig_seat is not None and (orig_seat.status == Seat.Status.AVAILABLE or still_held_by_this_ticket):
            reclaimed[ticket.pk] = orig_seat
            reclaimed_seat_ids.add(orig_seat.pk)
        else:
            needs_reassignment.append(ticket)

    if needs_reassignment:
        free_pool = [
            s for s in all_seats
            if s.status == Seat.Status.AVAILABLE and s.pk not in reclaimed_seat_ids
        ]
        passenger_types = [
            t.passenger.passenger_type if t.passenger_id else Passenger.Type.ADULT
            for t in needs_reassignment
        ]
        try:
            replacement_seats = select_automatic_seats(free_pool, passenger_types)
        except ValidationError:
            return False
    else:
        replacement_seats = []

    try:
        hold_duration = configured_hold_duration()
    except ReservationsClosed:
        hold_duration = timedelta(minutes=5)
    new_expires = now + hold_duration

    rep_iter = iter(replacement_seats)
    for ticket in tickets:
        assigned_seat = reclaimed.get(ticket.pk) or next(rep_iter)
        old_status = ticket.status
        old_seat_id = ticket.seat_id
        ticket.seat = assigned_seat
        ticket.status = Ticket.Status.HELD
        ticket.reservation_expires_at = new_expires
        ticket.save(update_fields=["seat", "status", "reservation_expires_at", "updated_at"])

        assigned_seat.status = Seat.Status.HELD
        assigned_seat.hold_expires_at = new_expires
        assigned_seat.save(update_fields=["status", "hold_expires_at", "updated_at"])

        if old_seat_id != assigned_seat.pk:
            TicketStatusHistory.objects.create(
                ticket=ticket,
                from_status=old_status,
                to_status=Ticket.Status.HELD,
                note=f"Nouvelle place attribuée ({assigned_seat.number}) après paiement tardif",
            )
        elif old_status != Ticket.Status.HELD:
            TicketStatusHistory.objects.create(
                ticket=ticket,
                from_status=old_status,
                to_status=Ticket.Status.HELD,
                note="Place reprise après paiement tardif",
            )

    locked_booking.status = Booking.Status.HELD
    locked_booking.reservation_expires_at = new_expires
    locked_booking.save(update_fields=["status", "reservation_expires_at", "updated_at"])
    return True


def _resolve_single_boarding_point(location, point_or_id, role_label: str):
    """
    Valide ou résout le point d'embarquement/débarquement pour `location` :
    - Si un point est fourni (instance ou identifiant), vérifie qu'il existe, appartient à `location` et est actif.
    - Si aucun point n'est fourni :
      * 0 point actif dans la ville → (None, "")
      * 1 seul point actif → présélectionné automatiquement (point, point.name)
      * plusieurs points actifs → erreur demandant un choix explicite.
    """
    if point_or_id is not None and point_or_id != "":
        if isinstance(point_or_id, BoardingPoint):
            point = point_or_id
        else:
            try:
                point = BoardingPoint.objects.select_related("location").get(pk=int(point_or_id))
            except (ValueError, TypeError, BoardingPoint.DoesNotExist) as exc:
                raise ValidationError(f"Point de {role_label} introuvable.") from exc
        if point.location_id != location.pk:
            raise ValidationError(
                f"Le point « {point.name} » n'appartient pas à la ville de {location.name} ({role_label})."
            )
        if not point.active:
            raise ValidationError(
                f"Le point « {point.name} » à {location.name} est désactivé et ne peut pas être choisi pour le {role_label}."
            )
        return point, point.name

    active_points = list(location.boarding_points.filter(active=True).order_by("order", "name", "id"))
    if not active_points:
        return None, ""
    if len(active_points) == 1:
        return active_points[0], active_points[0].name
    raise ValidationError(f"Veuillez choisir un point de {role_label} pour la ville de {location.name}.")


def resolve_boarding_points(origin_loc, dest_loc, boarding_point=None, alighting_point=None):
    b_point, b_name = _resolve_single_boarding_point(origin_loc, boarding_point, "embarquement")
    a_point, a_name = _resolve_single_boarding_point(dest_loc, alighting_point, "débarquement")
    return b_point, b_name, a_point, a_name


@transaction.atomic
def reserve_booking(
    *,
    trip,
    passengers,
    customer=None,
    contact_phone="",
    contact_email="",
    channel=Ticket.Channel.ONLINE,
    sold_by=None,
    idempotency_key="",
    buyer_ifu="",
    allow_departed=False,
    origin=None,
    destination=None,
    boarding_point=None,
    alighting_point=None,
):
    """
    Reserve all seats for a group or none of them.
    Départ déjà parti : refusé, sauf `allow_departed` (vente du contrôleur à l'arrêt, départs du jour seulement).
    """
    buyer_ifu = clean_buyer_ifu(buyer_ifu)
    if not 1 <= len(passengers) <= 8:
        raise ValidationError("Une réservation doit contenir entre 1 et 8 passagers.")

    release_expired_holds()
    locked_trip = Trip.objects.select_for_update().select_related("route").get(pk=trip.pk)
    if locked_trip.status not in {Trip.Status.SCHEDULED, Trip.Status.BOARDING}:
        raise ValidationError("Ce trajet n'accepte pas de nouvelle réservation.")
    if not allow_departed and locked_trip.departure_at <= timezone.now():
        raise ValidationError(DEPARTED_MESSAGE)

    all_trip_seats = list(Seat.objects.select_for_update().filter(trip=locked_trip))
    seats_by_pk = {seat.pk: seat for seat in all_trip_seats}

    chosen_seat_ids = [item["seat"].pk for item in passengers if item.get("seat") is not None]
    if len(chosen_seat_ids) != len(set(chosen_seat_ids)):
        raise ValidationError("Chaque passager doit avoir un siège différent.")
    if any(seat_id not in seats_by_pk for seat_id in chosen_seat_ids):
        raise ValidationError("Un ou plusieurs sièges ne correspondent pas au trajet sélectionné.")
    if any(seats_by_pk[seat_id].status != Seat.Status.AVAILABLE for seat_id in chosen_seat_ids):
        raise ValidationError(SEAT_JUST_TAKEN_MESSAGE)

    for item in passengers:
        passenger_type = item.get("passenger_type", Passenger.Type.ADULT)
        if passenger_type not in Passenger.Type.values:
            raise ValidationError("Le type d'un passager est invalide.")
        if item.get("seat") is not None:
            seat_obj = seats_by_pk[item["seat"].pk]
            allowed_types = seat_obj.allowed_passenger_types or []
            if allowed_types and passenger_type not in allowed_types:
                raise ValidationError(
                    f"Le siège {seat_obj.number} n'autorise pas ce type de passager."
                )

    unassigned_indices = [idx for idx, item in enumerate(passengers) if item.get("seat") is None]
    if unassigned_indices:
        chosen_set = set(chosen_seat_ids)
        free_pool = [
            s for s in all_trip_seats
            if s.status == Seat.Status.AVAILABLE and s.pk not in chosen_set
        ]
        unassigned_types = [
            passengers[idx].get("passenger_type", Passenger.Type.ADULT)
            for idx in unassigned_indices
        ]
        auto_seats = select_automatic_seats(free_pool, unassigned_types)
    else:
        auto_seats = []

    origin_loc = resolve_location(origin) if origin else None
    dest_loc = resolve_location(destination) if destination else None

    if (origin and not origin_loc) or (destination and not dest_loc):
        raise ValidationError("Arrêt de départ ou d'arrivée non reconnu.")

    if (origin_loc and not dest_loc) or (dest_loc and not origin_loc):
        raise ValidationError("Veuillez renseigner à la fois l'arrêt de montée et l'arrêt de descente.")

    if not origin_loc and not dest_loc:
        # Réservation sans tronçon spécifié : trajet complet par défaut
        origin_loc = locked_trip.route.origin
        dest_loc = locked_trip.route.destination

    if origin_loc.pk == dest_loc.pk:
        raise ValidationError("La ville de départ et la ville d'arrivée doivent être distinctes.")

    # Validation stricte : les deux arrêts sont sur la ligne du trajet et la montée précède la descente dans le sens du bus
    if not locked_trip.route.has_waypoint_direction(origin_loc, dest_loc):
        raise ValidationError(
            f"Le trajet {locked_trip.route.label} ne dessert pas le tronçon {origin_loc.name} vers {dest_loc.name} dans ce sens."
        )

    try:
        seg_fare = resolve_segment_fare(origin_loc, dest_loc)
        fare = SimpleNamespace(id=seg_fare.id, name=seg_fare.label, amount=Decimal(seg_fare.amount), currency=seg_fare.currency)
    except ImproperlyConfigured as exc:
        raise ValidationError(f"Aucun tarif n'est configuré pour le tronçon {origin_loc.name} → {dest_loc.name} : tronçon non vendable.") from exc

    b_point, b_name, a_point, a_name = resolve_boarding_points(
        origin_loc, dest_loc, boarding_point=boarding_point, alighting_point=alighting_point
    )

    expires_at = timezone.now() + configured_hold_duration()
    guest_token = secrets.token_urlsafe(32) if customer is None else None
    booking = Booking.objects.create(
        trip=locked_trip,
        customer=customer,
        contact_phone=contact_phone,
        contact_email=contact_email,
        guest_token_hash=hash_guest_token(guest_token) if guest_token else "",
        sold_by=sold_by,
        idempotency_key=idempotency_key,
        buyer_ifu=buyer_ifu,
        origin=origin_loc,
        destination=dest_loc,
        boarding_point=b_point,
        alighting_point=a_point,
        boarding_point_name=b_name,
        alighting_point_name=a_name,
        reservation_expires_at=expires_at,
        amount=fare.amount * Decimal(len(passengers)),
        currency=fare.currency,
    )

    taxes = _tax_snapshot(fare.amount)
    auto_iter = iter(auto_seats)
    for item in passengers:
        is_preferred = item.get("seat") is not None
        seat = seats_by_pk[item["seat"].pk] if is_preferred else next(auto_iter)
        passenger = Passenger.objects.create(
            booking=booking,
            full_name=item["full_name"],
            phone=item.get("phone", ""),
            passenger_type=item.get("passenger_type", Passenger.Type.ADULT),
        )
        ticket = Ticket.objects.create(
            booking=booking,
            passenger=passenger,
            trip=locked_trip,
            seat=seat,
            customer=customer,
            passenger_name=passenger.full_name,
            passenger_phone=passenger.phone,
            channel=channel,
            origin=origin_loc,
            destination=dest_loc,
            boarding_point=b_point,
            alighting_point=a_point,
            boarding_point_name=b_name,
            alighting_point_name=a_name,
            reservation_expires_at=expires_at,
            amount=fare.amount,
            currency=fare.currency,
            **taxes,
        )
        TicketStatusHistory.objects.create(
            ticket=ticket,
            to_status=Ticket.Status.HELD,
            changed_by=customer,
            note="" if is_preferred else AUTO_SEAT_NOTE,
        )
        seat.status = Seat.Status.HELD
        seat.hold_expires_at = expires_at
        seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
    return booking, guest_token


def require_receipt(receipt, *, ticket_id=None, booking_id=None):
    """Refuse toute émission qui n'est pas adossée à un reçu de paiement enregistré pour cette cible."""
    if not isinstance(receipt, PaymentReceipt) or receipt.pk is None:
        raise ValidationError("Aucune preuve de paiement vérifiée : émission refusée.")
    matches_ticket = ticket_id is not None and receipt.ticket_id == ticket_id
    matches_booking = booking_id is not None and receipt.booking_id == booking_id
    if not (matches_ticket or matches_booking):
        raise ValidationError("La preuve de paiement ne correspond pas à cette réservation.")


@transaction.atomic
def pay_and_issue_booking(booking, *, payment_method, receipt, actor=None, external_reference=""):
    """Issue every ticket in a booking atomically. Appelé uniquement par payments.py avec un reçu vérifié."""
    require_receipt(receipt, booking_id=booking.pk)
    locked = Booking.objects.select_for_update().get(pk=booking.pk)
    if locked.status != Booking.Status.HELD:
        raise ValidationError("Seule une réservation temporaire peut être payée.")
    if locked.reservation_expires_at and locked.reservation_expires_at <= timezone.now():
        raise ValidationError("La réservation temporaire a expiré.")

    tickets = list(locked.tickets.select_for_update().order_by("created_at"))
    if not tickets:
        raise ValidationError("Cette réservation ne contient aucun billet.")
    issued = []
    payments = []
    for ticket in tickets:
        confirmed_ticket, payment = pay_and_issue_ticket(
            ticket,
            payment_method=payment_method,
            receipt=receipt,
            actor=actor,
            external_reference=external_reference,
        )
        issued.append(confirmed_ticket)
        payments.append(payment)
    locked.status = Booking.Status.CONFIRMED
    locked.save(update_fields=["status", "updated_at"])
    return locked, issued, payments


@transaction.atomic
def reserve_ticket(
    *,
    trip,
    seat,
    customer,
    passenger_name,
    passenger_phone="",
    channel=Ticket.Channel.ONLINE,
    origin=None,
    destination=None,
    boarding_point=None,
    alighting_point=None,
):
    if trip.status not in {Trip.Status.SCHEDULED, Trip.Status.BOARDING}:
        raise ValidationError("Ce trajet n'accepte pas de nouvelle réservation.")
    if trip.departure_at <= timezone.now():
        raise ValidationError(DEPARTED_MESSAGE)
    if seat.trip_id != trip.id:
        raise ValidationError("Le siège ne correspond pas au trajet sélectionné.")
    locked_seat = Seat.objects.select_for_update().get(pk=seat.pk)
    if (
        locked_seat.status == Seat.Status.HELD
        and locked_seat.hold_expires_at
        and locked_seat.hold_expires_at <= timezone.now()
    ):
        stale_ticket = locked_seat.tickets.filter(status=Ticket.Status.HELD).order_by("-created_at").first()
        if stale_ticket:
            transition_ticket(stale_ticket, Ticket.Status.EXPIRED, actor=None, note="Expiration à la réservation")
        locked_seat.refresh_from_db()
    if locked_seat.status != Seat.Status.AVAILABLE:
        raise ValidationError("Ce siège n'est plus disponible.")

    origin_loc = resolve_location(origin) if origin else None
    dest_loc = resolve_location(destination) if destination else None

    if (origin and not origin_loc) or (destination and not dest_loc):
        raise ValidationError("Arrêt de départ ou d'arrivée non reconnu.")

    if (origin_loc and not dest_loc) or (dest_loc and not origin_loc):
        raise ValidationError("Veuillez renseigner à la fois l'arrêt de montée et l'arrêt de descente.")

    if not origin_loc and not dest_loc:
        origin_loc = trip.route.origin
        dest_loc = trip.route.destination

    if origin_loc.pk == dest_loc.pk:
        raise ValidationError("La ville de départ et la ville d'arrivée doivent être distinctes.")

    if not trip.route.has_waypoint_direction(origin_loc, dest_loc):
        raise ValidationError(
            f"Le trajet {trip.route.label} ne dessert pas le tronçon {origin_loc.name} vers {dest_loc.name} dans ce sens."
        )

    try:
        seg_fare = resolve_segment_fare(origin_loc, dest_loc)
        fare = SimpleNamespace(id=seg_fare.id, name=seg_fare.label, amount=Decimal(seg_fare.amount), currency=seg_fare.currency)
    except ImproperlyConfigured as exc:
        raise ValidationError(f"Aucun tarif n'est configuré pour le tronçon {origin_loc.name} → {dest_loc.name} : tronçon non vendable.") from exc

    b_point, b_name, a_point, a_name = resolve_boarding_points(
        origin_loc, dest_loc, boarding_point=boarding_point, alighting_point=alighting_point
    )

    expires_at = timezone.now() + configured_hold_duration()
    ticket = Ticket.objects.create(
        trip=trip,
        seat=locked_seat,
        customer=customer,
        passenger_name=passenger_name,
        passenger_phone=passenger_phone,
        channel=channel,
        origin=origin_loc,
        destination=dest_loc,
        boarding_point=b_point,
        alighting_point=a_point,
        boarding_point_name=b_name,
        alighting_point_name=a_name,
        reservation_expires_at=expires_at,
        amount=fare.amount,
        currency=fare.currency,
        **_tax_snapshot(fare.amount),
    )
    TicketStatusHistory.objects.create(ticket=ticket, to_status=Ticket.Status.HELD, changed_by=customer)
    locked_seat.status = Seat.Status.HELD
    locked_seat.hold_expires_at = expires_at
    locked_seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
    return ticket


@transaction.atomic
def transition_ticket(ticket, to_status, *, actor=None, note="", manual=False):
    locked = Ticket.objects.select_for_update().select_related("seat").get(pk=ticket.pk)
    if to_status not in TICKET_TRANSITIONS.get(locked.status, set()):
        raise ValidationError(f"Transition de billet interdite : {locked.status} → {to_status}.")
    from_status = locked.status
    locked.status = to_status
    locked.save(update_fields=["status", "updated_at"])
    TicketStatusHistory.objects.create(
        ticket=locked, from_status=from_status, to_status=to_status, changed_by=actor, note=note, manual=manual
    )
    if to_status in {Ticket.Status.CANCELLED, Ticket.Status.REFUNDED, Ticket.Status.EXPIRED}:
        locked.seat.status = Seat.Status.AVAILABLE
        locked.seat.hold_expires_at = None
        locked.seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
    elif to_status in {Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CHECKED, Ticket.Status.COMPLETED}:
        locked.seat.status = Seat.Status.PAID
        locked.seat.hold_expires_at = None
        locked.seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
    return locked


@transaction.atomic
def pay_and_issue_ticket(ticket, *, payment_method, receipt, actor=None, external_reference=""):
    require_receipt(receipt, ticket_id=ticket.pk, booking_id=ticket.booking_id)
    if not payment_method.active:
        raise ValidationError("Ce moyen de paiement n'est pas actif.")
    locked = Ticket.objects.select_for_update().get(pk=ticket.pk)
    if locked.status != Ticket.Status.HELD:
        raise ValidationError("Seul un billet temporairement réservé peut être payé.")
    if locked.reservation_expires_at and locked.reservation_expires_at <= timezone.now():
        transition_ticket(locked, Ticket.Status.EXPIRED, actor=actor)
        raise ValidationError("La réservation temporaire a expiré.")
    payment = Transaction.objects.create(
        payment_method=payment_method,
        amount=locked.amount,
        currency=locked.currency,
        status=Transaction.Status.SUCCEEDED,
        ticket=locked,
        external_reference=external_reference,
    )
    locked = transition_ticket(locked, Ticket.Status.PAID, actor=actor, note=f"Paiement {payment.reference}")
    locked = transition_ticket(locked, Ticket.Status.ISSUED, actor=actor, note="Émission après paiement confirmé")
    return locked, payment


def validate_ticket(*, qr_token, controller, expected_trip=None, method=TicketControl.Method.QR):
    with transaction.atomic():
        try:
            ticket = Ticket.objects.select_for_update().select_related("trip__route", "seat").get(qr_token=qr_token)
        except (Ticket.DoesNotExist, ValueError) as exc:
            raise ValidationError("Ticket introuvable.") from exc

        result = TicketControl.Result.ACCEPTED
        reason = ""
        if expected_trip and ticket.trip_id != expected_trip.id:
            result, reason = TicketControl.Result.REJECTED, "Le ticket ne correspond pas au voyage sélectionné."
        elif not expected_trip and timezone.localdate(ticket.trip.departure_at) != timezone.localdate():
            result, reason = TicketControl.Result.REJECTED, "Le ticket n'est pas valable à la date du contrôle."
        elif ticket.status == Ticket.Status.CHECKED or ticket.controls.filter(
            result=TicketControl.Result.ACCEPTED
        ).exists():
            result, reason = TicketControl.Result.ALREADY_USED, "Ce ticket a déjà été contrôlé."
        elif ticket.status != Ticket.Status.ISSUED:
            result, reason = (
                TicketControl.Result.REJECTED,
                f"Statut du ticket non valide : {ticket.get_status_display()}.",
            )

        control = TicketControl.objects.create(
            ticket=ticket, controller=controller, method=method, result=result, note=reason
        )
        if result == TicketControl.Result.ACCEPTED:
            ticket = transition_ticket(ticket, Ticket.Status.CHECKED, actor=controller, note=f"Contrôle {method}")
    if result != TicketControl.Result.ACCEPTED:
        raise ValidationError({"detail": reason, "result": result, "control_id": control.pk})
    return ticket, control


@transaction.atomic
def transition_parcel(parcel, to_status, *, actor=None, note=""):
    locked = Parcel.objects.select_for_update().get(pk=parcel.pk)
    if to_status not in PARCEL_TRANSITIONS.get(locked.status, set()):
        raise ValidationError(f"Transition de colis interdite : {locked.status} → {to_status}.")
    if to_status == Parcel.Status.ASSIGNED and not locked.trip_id:
        raise ValidationError("Un trajet doit être affecté au colis avant cette transition.")
    if to_status == Parcel.Status.PICKED_UP and not locked.pickup_recipient_identity:
        raise ValidationError("La preuve d'identité ou le code de retrait doit être renseigné.")
    from_status = locked.status
    locked.status = to_status
    locked.save(update_fields=["status", "updated_at"])
    ParcelStatusHistory.objects.create(
        parcel=locked, from_status=from_status, to_status=to_status, changed_by=actor, note=note
    )
    return locked


def rental_is_available(vehicle, starts_at, ends_at, exclude_booking=None):
    conflicts = RentalBooking.objects.filter(
        vehicle=vehicle,
        status__in=[RentalBooking.Status.REQUESTED, RentalBooking.Status.CONFIRMED, RentalBooking.Status.ACTIVE],
        starts_at__lt=ends_at,
        ends_at__gt=starts_at,
    )
    if exclude_booking:
        conflicts = conflicts.exclude(pk=exclude_booking.pk)
    return not conflicts.exists()


def _format_trip_stops_summary(trip):
    """
    Extrait l'origine, la destination et les escales intermédiaires
    ordonnées d'un voyage depuis RouteStop.
    """
    origin = trip.route.origin.name
    destination = trip.route.destination.name
    all_stops = list(trip.route.stops.select_related("location").order_by("position"))
    intermediate = [
        s.location.name
        for s in all_stops
        if s.location_id not in (trip.route.origin_id, trip.route.destination_id)
    ]
    stops_str = ", ".join(intermediate) if intermediate else ""
    return origin, destination, stops_str


def build_homepage_banner():
    """
    Construit le bandeau d'accueil dynamique côté serveur :
    « Aujourd'hui, le bus va de X vers Y et passe par A, B, C. Demain, il repart vers Z. »
    Cas gérés :
    - Pas de voyage aujourd'hui : « Pas de départ aujourd'hui. Prochain départ : jour, heure, départ → arrivée »
    - Voyage du jour déjà parti : « Le voyage d'aujourd'hui (X → Y) est déjà parti. Prochain départ : jour, heure, départ → arrivée »
    - Deux voyages le même jour : annonce des deux départs
    Fuseau : Bénin (UTC+1).
    """
    now = timezone.localtime()
    today = now.date()
    tomorrow = today + timedelta(days=1)

    today_trips = list(
        Trip.objects.filter(departure_at__date=today)
        .exclude(status=Trip.Status.CANCELLED)
        .select_related("route__origin", "route__destination")
        .prefetch_related("route__stops__location")
        .order_by("departure_at")
    )

    upcoming_trips = list(
        Trip.objects.filter(departure_at__gt=timezone.now(), status__in=[Trip.Status.SCHEDULED, Trip.Status.BOARDING])
        .select_related("route__origin", "route__destination")
        .prefetch_related("route__stops__location")
        .order_by("departure_at")
    )

    day_names = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    def _format_next_departure(next_trip):
        loc_dep = timezone.localtime(next_trip.departure_at)
        day_str = day_names[loc_dep.weekday()]
        time_str = loc_dep.strftime("%H:%M")
        date_str = loc_dep.strftime("%d/%m")
        return f"{day_str} {date_str} à {time_str}, {next_trip.route.origin.name} → {next_trip.route.destination.name}"

    # Cas 1 : Aucun voyage aujourd'hui (ex: jour de repos)
    if not today_trips:
        if upcoming_trips:
            next_info = _format_next_departure(upcoming_trips[0])
            banner_text = f"Pas de départ aujourd'hui. Prochain départ : {next_info}."
        else:
            banner_text = "Pas de départ aujourd'hui. Aucun départ à venir n'est actuellement publié."
        return {
            "banner_text": banner_text,
            "today_trips_count": 0,
            "has_departure_today": False,
        }

    # Départs du jour encore à venir (non partis)
    active_today = [
        t for t in today_trips
        if timezone.localtime(t.departure_at) > now and t.status in [Trip.Status.SCHEDULED, Trip.Status.BOARDING]
    ]

    # Cas 2 : Voyages aujourd'hui, mais déjà partis
    if not active_today:
        if len(today_trips) == 1:
            t0 = today_trips[0]
            dep_desc = f"{t0.route.origin.name} → {t0.route.destination.name}"
            intro = f"Le voyage d'aujourd'hui ({dep_desc}) est déjà parti."
        else:
            intro = "Les voyages d'aujourd'hui sont déjà partis."
        if upcoming_trips:
            next_info = _format_next_departure(upcoming_trips[0])
            banner_text = f"{intro} Prochain départ : {next_info}."
        else:
            banner_text = f"{intro} Aucun autre départ à venir n'est publié."
        return {
            "banner_text": banner_text,
            "today_trips_count": len(today_trips),
            "has_departure_today": False,
        }

    # Prochain départ après ceux d'aujourd'hui
    later_trips = [t for t in upcoming_trips if t.id not in [x.id for x in active_today]]
    tomorrow_text = ""
    if later_trips:
        nxt = later_trips[0]
        nxt_date = timezone.localtime(nxt.departure_at).date()
        if nxt_date == tomorrow:
            tomorrow_text = f" Demain, il repart vers {nxt.route.destination.name}."
        else:
            day_str = day_names[nxt_date.weekday()]
            time_str = timezone.localtime(nxt.departure_at).strftime("%H:%M")
            tomorrow_text = f" Prochain départ : {day_str} {nxt_date:%d/%m} à {time_str} ({nxt.route.origin.name} → {nxt.route.destination.name})."

    # Cas 3 : Un seul départ actif aujourd'hui
    if len(active_today) == 1:
        t = active_today[0]
        origin, destination, stops_str = _format_trip_stops_summary(t)
        if stops_str:
            base_text = f"Aujourd'hui, le bus va de {origin} vers {destination} et passe par {stops_str}."
        else:
            base_text = f"Aujourd'hui, le bus va de {origin} vers {destination}."
        banner_text = f"{base_text}{tomorrow_text}"
        return {
            "banner_text": banner_text,
            "today_trips_count": 1,
            "has_departure_today": True,
        }

    # Cas 4 : Deux ou plusieurs départs aujourd'hui
    desc_list = []
    for t in active_today:
        o, d, s = _format_trip_stops_summary(t)
        h = timezone.localtime(t.departure_at).strftime("%H:%M")
        if s:
            desc_list.append(f"{o} vers {d} à {h} (via {s})")
        else:
            desc_list.append(f"{o} vers {d} à {h}")
    trips_desc = " et ".join(desc_list)
    banner_text = f"Aujourd'hui, départs prévus : {trips_desc}.{tomorrow_text}"
    return {
        "banner_text": banner_text,
        "today_trips_count": len(active_today),
        "has_departure_today": True,
    }


def find_next_available_trip(origin, destination, after_date=None):
    """
    Recherche sans résultat : renvoie la prochaine date où le même tronçon
    est vendable (dans la limite des voyages déjà générés).
    """
    from datetime import datetime, time

    now = timezone.now()
    min_departure = now
    if after_date:
        try:
            d = datetime.strptime(str(after_date).strip(), "%Y-%m-%d").date()
            dt = timezone.make_aware(datetime.combine(d, time.min))
            if dt > min_departure:
                min_departure = dt
        except (ValueError, TypeError):
            pass

    candidate_qs = (
        Trip.objects.select_related("route__origin", "route__destination", "vehicle")
        .prefetch_related("seats")
        .filter(
            status__in=[Trip.Status.SCHEDULED, Trip.Status.BOARDING],
            departure_at__gte=min_departure,
        )
        .order_by("departure_at")
    )

    matching_trips = find_trips_for_waypoint_direction(candidate_qs, origin=origin, destination=destination)
    for trip in matching_trips:
        loc_dep = timezone.localtime(trip.departure_at)
        if after_date:
            try:
                target_d = datetime.strptime(str(after_date).strip(), "%Y-%m-%d").date()
                if loc_dep.date() <= target_d:
                    continue
            except (ValueError, TypeError):
                pass
        return {
            "trip_id": trip.id,
            "date": loc_dep.strftime("%Y-%m-%d"),
            "departure_at": trip.departure_at.isoformat(),
            "formatted_date": loc_dep.strftime("%d/%m/%Y"),
            "formatted_time": loc_dep.strftime("%H:%M"),
            "route_label": trip.route.label,
        }
    return None

