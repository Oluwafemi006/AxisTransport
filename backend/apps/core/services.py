import hashlib
import secrets
from datetime import timedelta
from decimal import Decimal

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
    Trip,
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


def configured_hold_duration():
    try:
        raw_value = SystemSetting.objects.get(key="ticket_hold_minutes").value
        minutes = int(raw_value)
    except (SystemSetting.DoesNotExist, TypeError, ValueError) as exc:
        raise ImproperlyConfigured(
            "Le paramètre administrable 'ticket_hold_minutes' doit être configuré avant toute réservation."
        ) from exc
    if minutes <= 0:
        raise ImproperlyConfigured("'ticket_hold_minutes' doit être un entier positif.")
    return timedelta(minutes=minutes)


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
):
    """Reserve all seats for a group or none of them."""
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

    fare = resolve_fare(locked_trip)
    expires_at = timezone.now() + configured_hold_duration()
    guest_token = secrets.token_urlsafe(32) if customer is None else None
    booking = Booking.objects.create(
        trip=locked_trip,
        customer=customer,
        contact_phone=contact_phone,
        contact_email=contact_email,
        guest_token_hash=hash_guest_token(guest_token) if guest_token else "",
        reservation_expires_at=expires_at,
        amount=fare.amount * Decimal(len(passengers)),
        currency=fare.currency,
    )

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
    fare = resolve_fare(trip)
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
    )
    TicketStatusHistory.objects.create(ticket=ticket, to_status=Ticket.Status.HELD, changed_by=customer)
    locked_seat.status = Seat.Status.HELD
    locked_seat.hold_expires_at = expires_at
    locked_seat.save(update_fields=["status", "hold_expires_at", "updated_at"])
    return ticket


@transaction.atomic
def transition_ticket(ticket, to_status, *, actor=None, note=""):
    locked = Ticket.objects.select_for_update().select_related("seat").get(pk=ticket.pk)
    if to_status not in TICKET_TRANSITIONS.get(locked.status, set()):
        raise ValidationError(f"Transition de billet interdite : {locked.status} → {to_status}.")
    from_status = locked.status
    locked.status = to_status
    locked.save(update_fields=["status", "updated_at"])
    TicketStatusHistory.objects.create(
        ticket=locked, from_status=from_status, to_status=to_status, changed_by=actor, note=note
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
