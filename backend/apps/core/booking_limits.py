"""Limites contre les réservations abusives en ligne : réservations non payées en cours, par téléphone ou par compte."""
from django.conf import settings
from django.core.exceptions import ValidationError
from django.utils import timezone

from .models import Booking

HELD_MESSAGE = (
    "Vous avez déjà une réservation en attente de paiement. Payez-la ou annulez-la avant d'en créer une autre."
)
SEATS_MESSAGE = "Trop de places sont déjà retenues avec ce numéro. Finalisez ou annulez votre réservation en cours."


def normalize_phone(value):
    """Chiffres seuls, sans indicatif du Bénin : « +229 01 00 00 00 09 » et « 0100000009 » sont le même numéro."""
    digits = "".join(character for character in str(value or "") if character.isdigit())
    if digits.startswith("00229"):
        digits = digits[5:]
    elif digits.startswith("229") and len(digits) > 10:
        digits = digits[3:]
    return digits


def _held_bookings(customer, contact_phone):
    held = Booking.objects.filter(
        status=Booking.Status.HELD, reservation_expires_at__gt=timezone.now()
    ).prefetch_related("tickets")
    if customer is not None:
        return list(held.filter(customer=customer))
    phone = normalize_phone(contact_phone)
    if not phone:
        return []
    return [booking for booking in held.filter(customer__isnull=True) if normalize_phone(booking.contact_phone) == phone]


def check_online_booking_limits(*, customer, contact_phone, seats):
    """Refuse une nouvelle réservation en ligne au-delà des seuils (réglables, voir DEPLOY.md)."""
    held = _held_bookings(customer, contact_phone)
    if len(held) >= settings.AXIS_BOOKING_MAX_HELD:
        raise ValidationError(HELD_MESSAGE)
    held_seats = sum(booking.tickets.count() for booking in held)
    if held_seats + seats > settings.AXIS_BOOKING_MAX_HELD_SEATS:
        raise ValidationError(SEATS_MESSAGE)
