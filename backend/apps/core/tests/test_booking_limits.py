from datetime import timedelta

from django.core.cache import cache
from django.test import override_settings
from django.utils import timezone
from rest_framework.settings import api_settings
from rest_framework.test import APITestCase

from apps.core.booking_limits import normalize_phone
from apps.core.models import Booking, Location, PaymentMethod, Route, SystemSetting, Ticket, Trip, User, Vehicle
from apps.core.services import generate_trip_seats

BOOKINGS = "/api/v1/client/bookings/"
LOOKUP = "/api/v1/client/tickets/lookup/"


def rates(**values):
    merged = {**api_settings.user_settings, "DEFAULT_THROTTLE_RATES": {**api_settings.DEFAULT_THROTTLE_RATES, **values}}
    return override_settings(REST_FRAMEWORK=merged)


class Base(APITestCase):
    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)
        parakou = Location.objects.create(name="Parakou", active=True)
        cotonou = Location.objects.create(name="Cotonou", active=True)
        from apps.core.models import LineStop, SegmentFare

        a = LineStop.objects.create(location=parakou, position=1)
        b = LineStop.objects.create(location=cotonou, position=2)
        SegmentFare.objects.create(start=a, end=b, amount=7500)
        route = Route.objects.create(origin=parakou, destination=cotonou)
        vehicle = Vehicle.objects.create(category=Vehicle.Category.BUS, name="TEST car", capacity=20)
        self.trip = Trip.objects.create(route=route, vehicle=vehicle, departure_at=timezone.now() + timedelta(days=2))
        generate_trip_seats(self.trip)
        SystemSetting.objects.create(key="ticket_hold_minutes", value=10)
        PaymentMethod.objects.create(code="FEDAPAY", label="Mobile Money", active=True)

    def book(self, phone="0163999755", passengers=1, **extra):
        return self.client.post(
            BOOKINGS,
            {"trip": self.trip.pk, "contact_phone": phone,
             "passengers": [{"full_name": f"TEST Passager {i}", "phone": phone} for i in range(passengers)]},
            format="json", **extra,
        )


@override_settings(AXIS_BOOKING_MAX_HELD=2, AXIS_BOOKING_MAX_HELD_SEATS=8)
class HeldLimitTests(Base):
    def test_third_unpaid_booking_with_the_same_phone_is_refused(self):
        self.assertEqual(self.book().status_code, 201)
        self.assertEqual(self.book("+229 01 63 99 97 55").status_code, 201)
        third = self.book("22901 63 99 97 55")
        self.assertEqual(third.status_code, 400)
        self.assertIn("déjà une réservation en attente", str(third.data))

    def test_paid_or_expired_booking_no_longer_counts(self):
        self.book(); self.book()
        Booking.objects.update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        self.assertEqual(self.book().status_code, 201)
        Booking.objects.filter(status=Booking.Status.HELD).update(status=Booking.Status.CONFIRMED)
        self.assertEqual(self.book().status_code, 201)

    def test_too_many_held_seats_is_refused(self):
        self.assertEqual(self.book(passengers=6).status_code, 201)
        response = self.book(passengers=3)
        self.assertEqual(response.status_code, 400)
        self.assertIn("Trop de places", str(response.data))

    def test_two_phones_behind_one_address_each_have_their_own_limit(self):
        for phone in ("0163999755", "0197000000"):
            self.assertEqual(self.book(phone, REMOTE_ADDR="10.0.0.9").status_code, 201)
            self.assertEqual(self.book(phone, REMOTE_ADDR="10.0.0.9").status_code, 201)

    def test_logged_client_is_counted_by_account(self):
        client = User.objects.create_user(username="test_client_lim", password="s", role=User.Role.CLIENT)
        self.client.force_authenticate(client)
        self.book("0100000001"); self.book("0100000002")
        self.assertEqual(self.book("0100000003").status_code, 400)

    def test_staff_is_never_limited(self):
        counter = User.objects.create_user(username="test_guichet_lim", password="s", role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        for _ in range(3):
            response = self.client.post("/api/v1/bookings/", {"trip": self.trip.pk, "contact_phone": "0163999755",
                                        "passengers": [{"full_name": "TEST G", "phone": "0163999755"}]}, format="json")
            self.assertEqual(response.status_code, 201, response.data)


class RateTests(Base):
    def test_creations_per_address_are_limited_with_retry_after(self):
        with rates(booking_address="2/hour", booking_phone="100/hour"):
            self.book("0100000001", REMOTE_ADDR="10.1.1.1")
            self.book("0100000002", REMOTE_ADDR="10.1.1.1")
            blocked = self.book("0100000003", REMOTE_ADDR="10.1.1.1")
        self.assertEqual(blocked.status_code, 429)
        self.assertTrue(int(blocked["Retry-After"]) > 0)

    def test_creations_per_phone_are_limited(self):
        with rates(booking_address="100/hour", booking_phone="1/hour"):
            self.book()
            self.assertEqual(self.book("+229 0163999755").status_code, 429)

    def test_normalize_phone(self):
        self.assertEqual({normalize_phone(v) for v in ("0163999755", "+229 01 63 99 97 55", "00229 01 63 99 97 55", "22901 63 99 97 55")}, {"0163999755"})


class LookupTests(Base):
    def setUp(self):
        super().setUp()
        booking_id = self.book().data["id"]
        self.ticket = Ticket.objects.get(booking_id=booking_id)

    def look(self, reference, phone, **extra):
        return self.client.post(LOOKUP, {"reference": reference, "phone": phone}, format="json", **extra)

    def test_good_reference_and_phone_return_only_the_reference(self):
        response = self.look(self.ticket.reference.lower(), "+229 01 63 99 97 55")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"reference": self.ticket.reference})

    def test_same_refusal_for_wrong_phone_or_unknown_reference(self):
        wrong = self.look(self.ticket.reference, "0100000000")
        unknown = self.look("AX-00000000-DEADBEEF", "0163999755")
        self.assertEqual((wrong.status_code, wrong.json()), (unknown.status_code, unknown.json()))
        self.assertEqual(wrong.status_code, 404)

    def test_attempts_are_limited_per_reference(self):
        for index in range(5):
            self.look(self.ticket.reference, f"010000000{index}", REMOTE_ADDR=f"10.2.2.{index}")
        self.assertEqual(self.look(self.ticket.reference, "0163999755", REMOTE_ADDR="10.2.2.9").status_code, 429)
