from unittest import mock

from django.test import override_settings
from rest_framework.test import APITestCase

from apps.core.models import Booking, Passenger, PaymentMethod, Seat, Ticket

from .factories import build_operational_context


class BookingApiTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()

    def _passenger(self, *, name, seat, passenger_type=Passenger.Type.ADULT):
        return {
            "full_name": name,
            "phone": "90000000",
            "passenger_type": passenger_type,
            "seat": seat.pk,
        }

    def test_guest_can_create_retrieve_and_pay_group_booking_with_token(self):
        trip = self.context["trip"]
        seats = list(trip.seats.order_by("number")[:2])
        response = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": trip.pk,
                "contact_phone": "90000000",
                "passengers": [
                    self._passenger(name="Premier Voyageur", seat=seats[0]),
                    self._passenger(name="Deuxième Voyageur", seat=seats[1], passenger_type=Passenger.Type.CHILD),
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        booking_id = response.data["id"]
        guest_token = response.data["guest_access_token"]
        self.assertEqual(response.data["status"], Booking.Status.HELD)
        self.assertEqual(len(response.data["passengers"]), 2)
        self.assertEqual(Ticket.objects.filter(booking_id=booking_id, status=Ticket.Status.HELD).count(), 2)

        forbidden = self.client.get(f"/api/v1/client/bookings/{booking_id}/")
        self.assertEqual(forbidden.status_code, 403)

        self.client.credentials(HTTP_X_BOOKING_TOKEN=guest_token)
        retrieved = self.client.get(f"/api/v1/client/bookings/{booking_id}/")
        self.assertEqual(retrieved.status_code, 200)

        # Sans preuve de paiement vérifiée, rien n'est émis.
        unpaid = self.client.post(
            f"/api/v1/client/bookings/{booking_id}/pay/",
            {"payment_method": self.context["payment_method"].pk},
            format="json",
        )
        self.assertEqual(unpaid.status_code, 400, unpaid.data)
        self.assertEqual(Ticket.objects.filter(booking_id=booking_id, status=Ticket.Status.HELD).count(), 2)

        fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        verified = {
            "id": 4242,
            "status": "approved",
            "amount": 2000,
            "currency": {"iso": "XOF"},
            "custom_metadata": {"booking_id": booking_id},
        }
        with override_settings(FEDAPAY_SECRET_KEY="sk_sandbox_test"), mock.patch(
            "apps.core.payments._fedapay_fetch_transaction", return_value=verified
        ):
            paid = self.client.post(
                f"/api/v1/client/bookings/{booking_id}/pay/",
                {"payment_method": fedapay.pk, "external_reference": "4242"},
                format="json",
            )
        self.assertEqual(paid.status_code, 200, paid.data)
        self.assertEqual(paid.data["booking"]["status"], Booking.Status.CONFIRMED)
        self.assertEqual(
            {ticket["status"] for ticket in paid.data["booking"]["tickets"]},
            {Ticket.Status.ISSUED},
        )
        self.assertEqual(
            Seat.objects.filter(pk__in=[seat.pk for seat in seats], status=Seat.Status.PAID).count(),
            2,
        )

    def test_duplicate_seat_is_rejected_without_creating_booking(self):
        trip = self.context["trip"]
        seat = trip.seats.first()
        response = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": trip.pk,
                "passengers": [
                    self._passenger(name="Premier Voyageur", seat=seat),
                    self._passenger(name="Deuxième Voyageur", seat=seat),
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(Booking.objects.count(), 0)
        self.assertEqual(Ticket.objects.count(), 0)
        seat.refresh_from_db()
        self.assertEqual(seat.status, Seat.Status.AVAILABLE)

    def test_placement_rule_rejects_incompatible_passenger_type(self):
        trip = self.context["trip"]
        seat = trip.seats.first()
        seat.allowed_passenger_types = [Passenger.Type.ADULT]
        seat.save(update_fields=["allowed_passenger_types", "updated_at"])

        response = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": trip.pk,
                "passengers": [
                    self._passenger(name="Enfant Voyageur", seat=seat, passenger_type=Passenger.Type.CHILD),
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("Le siège", str(response.data))
        self.assertEqual(Booking.objects.count(), 0)
        seat.refresh_from_db()
        self.assertEqual(seat.status, Seat.Status.AVAILABLE)
