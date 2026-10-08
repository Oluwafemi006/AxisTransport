from datetime import timedelta

from django.core.exceptions import ValidationError
from django.test import TestCase
from django.utils import timezone

from apps.core.models import Seat, Ticket, TicketControl
from apps.core.payments import settle_ticket_payment
from apps.core.services import (
    release_expired_holds,
    reserve_ticket,
    transition_ticket,
    validate_ticket,
)

from .factories import build_operational_context


class TicketLifecycleTests(TestCase):
    def setUp(self):
        self.context = build_operational_context()

    def test_complete_ticket_lifecycle_and_prevent_second_control(self):
        trip = self.context["trip"]
        seat = trip.seats.first()
        ticket = reserve_ticket(
            trip=trip,
            seat=seat,
            customer=self.context["client"],
            passenger_name="Client Test",
        )
        self.assertEqual(ticket.status, Ticket.Status.HELD)
        seat.refresh_from_db()
        self.assertEqual(seat.status, Seat.Status.HELD)

        # Moyen de paiement manuel : seul un agent habilité peut attester l'encaissement.
        with self.assertRaises(ValidationError):
            settle_ticket_payment(
                ticket, payment_method=self.context["payment_method"], actor=self.context["client"]
            )
        settlement = settle_ticket_payment(
            ticket, payment_method=self.context["payment_method"], actor=self.context["admin"]
        )
        ticket, payment = settlement.target, settlement.transactions[0]
        self.assertEqual(ticket.status, Ticket.Status.ISSUED)
        self.assertEqual(payment.ticket, ticket)

        ticket, first_control = validate_ticket(
            qr_token=ticket.qr_token,
            controller=self.context["controller"],
            expected_trip=trip,
        )
        self.assertEqual(ticket.status, Ticket.Status.CHECKED)
        self.assertEqual(first_control.result, TicketControl.Result.ACCEPTED)

        with self.assertRaises(ValidationError):
            validate_ticket(
                qr_token=ticket.qr_token,
                controller=self.context["controller"],
                expected_trip=trip,
            )
        self.assertEqual(ticket.controls.count(), 2)

        ticket = transition_ticket(ticket, Ticket.Status.COMPLETED, actor=self.context["admin"])
        self.assertEqual(ticket.status, Ticket.Status.COMPLETED)
        self.assertEqual(
            list(ticket.status_history.values_list("to_status", flat=True)),
            [Ticket.Status.HELD, Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CHECKED, Ticket.Status.COMPLETED],
        )

    def test_expired_hold_releases_seat(self):
        seat = self.context["trip"].seats.first()
        ticket = reserve_ticket(
            trip=self.context["trip"],
            seat=seat,
            customer=self.context["client"],
            passenger_name="Client Test",
        )
        Ticket.objects.filter(pk=ticket.pk).update(reservation_expires_at=timezone.now() - timedelta(seconds=1))
        Seat.objects.filter(pk=seat.pk).update(hold_expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(release_expired_holds(), 1)
        ticket.refresh_from_db()
        seat.refresh_from_db()
        self.assertEqual(ticket.status, Ticket.Status.EXPIRED)
        self.assertEqual(seat.status, Seat.Status.AVAILABLE)

