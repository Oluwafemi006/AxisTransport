"""Suppression d'un compte client à sa demande : anonymisation, jamais de suppression des lignes liées.
Billets, réservations, colis, locations et paiements restent en base (comptabilité), sans nom ni coordonnées."""
import uuid

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import AccountChange, Booking, Parcel, Passenger, PasswordResetCode, Ticket, User
from .password_reset import close_sessions

ANONYMOUS_NAME = "Client supprimé"
# Billet payé dont le voyage n'est pas encore parti : le client doit pouvoir le présenter, la suppression attend.
ACTIVE_TICKET_STATUSES = (Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CHECKED)


def upcoming_paid_tickets(user):
    return Ticket.objects.filter(
        Q(customer=user) | Q(booking__customer=user),
        status__in=ACTIVE_TICKET_STATUSES,
        trip__departure_at__gt=timezone.now(),
    )


@transaction.atomic
def delete_client_account(user, password):
    if user.role != User.Role.CLIENT:
        raise PermissionError("Un compte du personnel ne se supprime pas ici : adressez-vous à un administrateur.")
    if not user.check_password(str(password or "")):
        raise ValidationError({"password": "Mot de passe incorrect."})
    user = User.objects.select_for_update().get(pk=user.pk)
    if upcoming_paid_tickets(user).exists():
        raise ValidationError({"detail": "Vous avez un billet payé pour un voyage qui n’est pas encore parti. "
                                         "Vous pourrez supprimer votre compte après ce voyage."})
    bookings = Booking.objects.filter(customer=user)
    tickets = Ticket.objects.filter(Q(customer=user) | Q(booking__customer=user))
    tickets.update(passenger_name=ANONYMOUS_NAME, passenger_phone="")
    Passenger.objects.filter(booking__in=bookings).update(full_name=ANONYMOUS_NAME, phone="")
    bookings.update(contact_phone="", contact_email="", buyer_ifu="")
    Parcel.objects.filter(customer=user).update(
        sender_name=ANONYMOUS_NAME, sender_phone="", recipient_name=ANONYMOUS_NAME, recipient_phone="",
        pickup_recipient_identity="",
    )
    PasswordResetCode.objects.filter(user=user).delete()
    user.username = f"supprime-{user.pk}-{uuid.uuid4().hex[:8]}"
    user.first_name = user.last_name = user.phone = user.email = ""
    user.set_unusable_password()
    user.is_active = False
    user.save(update_fields=["username", "first_name", "last_name", "phone", "email", "password", "is_active"])
    close_sessions(user)
    AccountChange.objects.create(
        target=user, actor=None, action=AccountChange.Action.DEACTIVATED,
        detail="Compte supprimé à la demande du client (données personnelles anonymisées).",
    )
