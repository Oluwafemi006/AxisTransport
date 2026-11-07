"""Suppression du compte par le client : anonymisation, refus si un voyage payé n'est pas parti, personnel refusé."""
from datetime import timedelta

from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    AccountChange, Booking, Parcel, Passenger, PasswordResetCode, PaymentAttempt, PaymentMethod, RentalBooking, Ticket,
    Transaction, User, Vehicle,
)

from .factories import build_operational_context

ME = "/api/v1/auth/me/"
TOKEN = "/api/v1/auth/token/"
PASSWORD = "TEST-Mdp-suppr-42"


class AccountDeletionTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.context = build_operational_context()
        self.user = User.objects.create_user(
            username="test_suppr", password=PASSWORD, role=User.Role.CLIENT,
            first_name="TEST", last_name="Client", phone="0197000099", email="suppr.test@exemple.test",
        )
        self.trip = self.context["trip"]

    def ticket(self, status, *, departure_delta):
        self.trip.departure_at = timezone.now() + departure_delta
        self.trip.save(update_fields=["departure_at"])
        booking = Booking.objects.create(trip=self.trip, customer=self.user, amount=1000, contact_phone="0197000099", contact_email="suppr.test@exemple.test", buyer_ifu="TEST-IFU")
        Passenger.objects.create(booking=booking, full_name="TEST Passager", phone="0197000098")
        seat = self.trip.seats.order_by("id").first()
        return Ticket.objects.create(
            trip=self.trip, seat=seat, booking=booking, customer=self.user, passenger_name="TEST Passager",
            passenger_phone="0197000098", amount=1000, status=status,
        )

    def delete(self, password=PASSWORD):
        self.client.force_authenticate(self.user)
        return self.client.delete(ME, {"password": password}, format="json")

    def test_wrong_or_missing_password_is_refused_and_nothing_changes(self):
        for password in ("TEST-faux", ""):
            self.assertEqual(self.delete(password).status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_active)
        self.assertEqual(self.user.email, "suppr.test@exemple.test")

    def test_paid_ticket_for_a_trip_not_yet_departed_blocks_deletion(self):
        self.ticket(Ticket.Status.ISSUED, departure_delta=timedelta(days=2))
        response = self.delete()
        self.assertEqual(response.status_code, 400)
        self.assertIn("pas encore parti", str(response.data))
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_active)

    def test_account_is_anonymised_history_kept_and_login_impossible(self):
        ticket = self.ticket(Ticket.Status.COMPLETED, departure_delta=timedelta(days=-2))
        Transaction.objects.create(payment_method=self.context["payment_method"], amount=ticket.amount, currency="XOF", ticket=ticket, status=Transaction.Status.SUCCEEDED)
        parcel = Parcel.objects.create(
            origin=self.context["origin"], destination=self.context["destination"], customer=self.user,
            sender_name="TEST Expéditeur", sender_phone="0197000097", recipient_name="TEST Destinataire",
            recipient_phone="0197000096", description="TEST colis", status=Parcel.Status.PICKED_UP,
        )
        PasswordResetCode.objects.create(user=self.user, code_hash="TEST", expires_at=timezone.now())
        self.assertEqual(self.delete().status_code, 204)

        self.user.refresh_from_db()
        self.assertFalse(self.user.is_active)
        self.assertFalse(self.user.has_usable_password())
        self.assertEqual((self.user.first_name, self.user.last_name, self.user.phone, self.user.email), ("", "", "", ""))
        self.assertTrue(self.user.username.startswith("supprime-"))
        ticket.refresh_from_db(); parcel.refresh_from_db()
        self.assertEqual((ticket.passenger_name, ticket.passenger_phone, ticket.status), ("Client supprimé", "", Ticket.Status.COMPLETED))
        self.assertEqual(Transaction.objects.filter(ticket=ticket).count(), 1)
        self.assertEqual(Passenger.objects.get(booking=ticket.booking).full_name, "Client supprimé")
        booking = Booking.objects.get(pk=ticket.booking_id)
        self.assertEqual((booking.contact_phone, booking.contact_email, booking.buyer_ifu), ("", "", ""))
        self.assertEqual((parcel.sender_name, parcel.sender_phone, parcel.recipient_phone), ("Client supprimé", "", ""))
        self.assertFalse(PasswordResetCode.objects.filter(user=self.user).exists())
        self.assertTrue(AccountChange.objects.filter(target=self.user, detail__contains="supprimé").exists())
        self.client.force_authenticate(None)
        self.assertNotEqual(self.client.post(TOKEN, {"username": "test_suppr", "password": PASSWORD}, format="json").status_code, 200)

    def test_open_session_tokens_are_invalidated(self):
        self.client.force_authenticate(None)
        tokens = self.client.post(TOKEN, {"username": "test_suppr", "password": PASSWORD}, format="json").json()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        self.assertEqual(self.client.delete(ME, {"password": PASSWORD}, format="json").status_code, 204)
        self.assertEqual(self.client.get(ME).status_code, 401)
        self.client.credentials()
        self.assertNotEqual(self.client.post("/api/v1/auth/token/refresh/", {"refresh": tokens["refresh"]}, format="json").status_code, 200)

    def parcel(self, status):
        return Parcel.objects.create(
            origin=self.context["origin"], destination=self.context["destination"], customer=self.user,
            sender_name="TEST", sender_phone="0197000097", recipient_name="TEST", recipient_phone="0197000096",
            description="TEST colis", status=status,
        )

    def rental(self, status):
        car = Vehicle.objects.create(category=Vehicle.Category.RENTAL, name="TEST voiture suppr")
        start = timezone.now() + timedelta(days=3)
        return RentalBooking.objects.create(vehicle=car, customer=self.user, starts_at=start, ends_at=start + timedelta(days=1), status=status)

    def assert_refused(self, words):
        response = self.delete()
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn(words, str(response.data))
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_active)

    def test_parcel_not_picked_up_blocks_deletion_in_every_open_status(self):
        parcel = self.parcel(Parcel.Status.REGISTERED)
        for status in (s for s in Parcel.Status.values if s not in {"PICKED_UP", "CANCELLED"}):
            Parcel.objects.filter(pk=parcel.pk).update(status=status)
            self.assert_refused("colis")
        for status in ("PICKED_UP", "CANCELLED"):
            Parcel.objects.filter(pk=parcel.pk).update(status=status)
            self.assertNotIn("colis", str(self.client.delete(ME, {"password": "TEST-faux"}, format="json").data))

    def test_open_rental_blocks_deletion_finished_one_does_not(self):
        rental = self.rental(RentalBooking.Status.REQUESTED)
        for status in ("REQUESTED", "CONFIRMED", "ACTIVE"):
            RentalBooking.objects.filter(pk=rental.pk).update(status=status)
            self.assert_refused("location")
        RentalBooking.objects.filter(pk=rental.pk).update(status=RentalBooking.Status.COMPLETED)
        self.assertEqual(self.delete().status_code, 204)

    def test_pending_mobile_money_attempt_blocks_deletion(self):
        ticket = self.ticket(Ticket.Status.HELD, departure_delta=timedelta(days=2))
        attempt = PaymentAttempt.objects.create(provider="FEDAPAY", external_id="TEST-1", amount=1000, booking=ticket.booking)
        self.assert_refused("Mobile Money")
        PaymentAttempt.objects.filter(pk=attempt.pk).update(outcome=PaymentAttempt.Outcome.ABANDONED)
        self.assertEqual(self.delete().status_code, 204)

    def test_pending_mobile_money_transaction_blocks_deletion(self):
        method, _ = PaymentMethod.objects.get_or_create(code="FEDAPAY", defaults={"label": "TEST Mobile Money", "active": True})
        rental = self.rental(RentalBooking.Status.COMPLETED)
        Transaction.objects.create(payment_method=method, amount=1000, currency="XOF", rental=rental, status=Transaction.Status.PENDING, external_reference="TEST-2")
        self.assert_refused("Mobile Money")

    def test_staff_accounts_are_refused(self):
        for role in (User.Role.COUNTER, User.Role.CONTROLLER, User.Role.ADMIN):
            staff = User.objects.create_user(username=f"test_{role.lower()}", password=PASSWORD, role=role)
            self.client.force_authenticate(staff)
            self.assertEqual(self.client.delete(ME, {"password": PASSWORD}, format="json").status_code, 403, role)
            staff.refresh_from_db()
            self.assertTrue(staff.is_active)

    def test_visitor_is_refused(self):
        self.assertEqual(self.client.delete(ME, {"password": PASSWORD}, format="json").status_code, 401)
