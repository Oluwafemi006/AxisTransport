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
    SegmentFare,
    SegmentFareChange,
    Tax,
)


TICKET_TRANSITIONS = {
    Ticket.Status.HELD: {Ticket.Status.PAID, Ticket.Status.CANCELLED, Ticket.Status.EXPIRED},
    Ticket.Status.PAID: {Ticket.Status.ISSUED, Ticket.Status.CANCELLED, Ticket.Status.REFUNDED},
    Ticket.Status.ISSUED: {Ticket.Status.CHECKED, Ticket.Status.CANCELLED, Ticket.Status.REFUNDED},
    Ticket.Status.CHECKED: {Ticket.Status.COMPLETED},
    Ticket.Status.COMPLETED: set(),
    Ticket.Status.CANCELLED: set(),
    Ticket.Status.REFUNDED: set(),
    Ticket.Status.EXPIRED: set(),
}

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
):
    """Reserve all seats for a group or none of them."""
    buyer_ifu = clean_buyer_ifu(buyer_ifu)
    if not 1 <= len(passengers) <= 8:
        raise ValidationError("Une réservation doit contenir entre 1 et 8 passagers.")

    release_expired_holds()
    locked_trip = Trip.objects.select_for_update().select_related("route").get(pk=trip.pk)
    if locked_trip.status not in {Trip.Status.SCHEDULED, Trip.Status.BOARDING}:
        raise ValidationError("Ce trajet n'accepte pas de nouvelle réservation.")

    seat_ids = [item["seat"].pk for item in passengers]
    if len(seat_ids) != len(set(seat_ids)):
        raise ValidationError("Chaque passager doit avoir un siège différent.")
    seats = {
        seat.pk: seat
        for seat in Seat.objects.select_for_update().filter(trip=locked_trip, pk__in=seat_ids)
    }
    if len(seats) != len(seat_ids):
        raise ValidationError("Un ou plusieurs sièges ne correspondent pas au trajet sélectionné.")
    if any(seats[seat_id].status != Seat.Status.AVAILABLE for seat_id in seat_ids):
        raise ValidationError("Un ou plusieurs sièges ne sont plus disponibles.")

    for item in passengers:
        passenger_type = item.get("passenger_type", Passenger.Type.ADULT)
        if passenger_type not in Passenger.Type.values:
            raise ValidationError("Le type d'un passager est invalide.")
        allowed_types = seats[item["seat"].pk].allowed_passenger_types or []
        if allowed_types and passenger_type not in allowed_types:
            raise ValidationError(
                f"Le siège {item['seat'].number} n'autorise pas ce type de passager."
            )

    fare = trip_fare(locked_trip)
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
        reservation_expires_at=expires_at,
        amount=fare.amount * Decimal(len(passengers)),
        currency=fare.currency,
    )

    taxes = _tax_snapshot(fare.amount)
    for item in passengers:
        seat = seats[item["seat"].pk]
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
            reservation_expires_at=expires_at,
            amount=fare.amount,
            currency=fare.currency,
            **taxes,
        )
        TicketStatusHistory.objects.create(ticket=ticket, to_status=Ticket.Status.HELD, changed_by=customer)
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
def reserve_ticket(*, trip, seat, customer, passenger_name, passenger_phone="", channel=Ticket.Channel.ONLINE):
    if trip.status not in {Trip.Status.SCHEDULED, Trip.Status.BOARDING}:
        raise ValidationError("Ce trajet n'accepte pas de nouvelle réservation.")
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
    fare = trip_fare(trip)
    expires_at = timezone.now() + configured_hold_duration()
    ticket = Ticket.objects.create(
        trip=trip,
        seat=locked_seat,
        customer=customer,
        passenger_name=passenger_name,
        passenger_phone=passenger_phone,
        channel=channel,
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
