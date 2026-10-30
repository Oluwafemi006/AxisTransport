from datetime import datetime, time, timedelta
from io import StringIO

from django.core.cache import cache
from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    Booking,
    LineStop,
    Location,
    PaymentMethod,
    Route,
    SegmentFare,
    SegmentFareChange,
    SystemSetting,
    Ticket,
    Trip,
    User,
    Vehicle,
)
from apps.core.services import generate_trip_seats

SEGMENTS = "/api/v1/client/segments/"
TRIPS = "/api/v1/client/trips/"
ORDER = ["Parakou", "Savè", "Kétou", "Porto-Novo", "Cotonou"]
GRID = {
    ("Parakou", "Savè"): 4500, ("Parakou", "Kétou"): 6500, ("Parakou", "Porto-Novo"): 7500, ("Parakou", "Cotonou"): 7500,
    ("Savè", "Kétou"): 2500, ("Savè", "Porto-Novo"): 6500, ("Savè", "Cotonou"): 6500,
    ("Kétou", "Porto-Novo"): 4000, ("Kétou", "Cotonou"): 4000, ("Porto-Novo", "Cotonou"): 1500,
}


class SegmentsTestCase(APITestCase):
    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)
        call_command("load_segment_fares", stdout=StringIO())
        Location.objects.update(active=True)
        self.places = {location.name: location for location in Location.objects.all()}
        self.forward = Route.objects.create(origin=self.places["Parakou"], destination=self.places["Cotonou"])
        self.backward = Route.objects.create(origin=self.places["Cotonou"], destination=self.places["Parakou"])
        self.vehicle = Vehicle.objects.create(category=Vehicle.Category.BUS, name="TEST car", capacity=4)
        SystemSetting.objects.create(key="ticket_hold_minutes", value=10)

    def departure(self, route, days=1):
        trip = Trip.objects.create(route=route, vehicle=self.vehicle, departure_at=timezone.now() + timedelta(days=days))
        generate_trip_seats(trip)
        return trip

    def segments(self, direction="aller"):
        response = self.client.get(SEGMENTS, {"direction": direction})
        self.assertEqual(response.status_code, 200, response.data)
        return response.json()

    def drop_fare(self, first, second):
        fares = SegmentFare.objects.filter(start__location__name=first, end__location__name=second)
        SegmentFareChange.objects.filter(fare__in=fares).delete()
        fares.delete()

    def assert_fare_missing(self, response):
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "segment_fare_missing")
        self.assertIn("Tarif non disponible", str(response.data["detail"]))


class SegmentCatalogTests(SegmentsTestCase):
    def test_ten_pairs_in_stop_order_with_their_prices_on_the_way_out(self):
        rows = self.segments()["segments"]
        self.assertEqual(
            [(row["origin"], row["destination"], row["price_fcfa"]) for row in rows],
            [(first, second, GRID[(first, second)]) for first_i, first in enumerate(ORDER) for second in ORDER[first_i + 1:]],
        )

    def test_ten_pairs_in_stop_order_with_the_same_prices_on_the_way_back(self):
        rows = self.segments("retour")["segments"]
        back = ORDER[::-1]
        self.assertEqual(
            [(row["origin"], row["destination"], row["price_fcfa"]) for row in rows],
            [(first, second, GRID[(second, first)]) for first_i, first in enumerate(back) for second in back[first_i + 1:]],
        )

    def test_pair_without_fare_is_listed_in_missing_fares_only(self):
        self.drop_fare("Savè", "Kétou")
        payload = self.segments()
        self.assertEqual(len(payload["segments"]), 9)
        self.assertNotIn(("Savè", "Kétou"), [(row["origin"], row["destination"]) for row in payload["segments"]])
        self.assertEqual(
            [(row["origin"], row["destination"]) for row in payload["missing_fares"]], [("Savè", "Kétou")]
        )

    def test_inactive_stop_gives_no_pair(self):
        Location.objects.filter(name="Kétou").update(active=False)
        cache.clear()
        names = {row["origin"] for row in self.segments()["segments"]} | {row["destination"] for row in self.segments()["segments"]}
        self.assertNotIn("Kétou", names)

    def test_next_departure_is_the_first_bus_of_this_direction(self):
        self.departure(self.backward, days=1)
        later = self.departure(self.forward, days=3)
        self.departure(self.forward, days=5)
        row = self.segments()["segments"][0]
        self.assertEqual(row["line_origin"], "Parakou")
        self.assertEqual(row["next_departure"][:16], timezone.localtime(later.departure_at).isoformat()[:16])

    def test_no_future_departure_gives_null(self):
        row = self.segments("retour")["segments"][0]
        self.assertIsNone(row["next_departure"])
        self.assertEqual(row["line_origin"], "Cotonou")

    def test_unknown_direction_is_refused(self):
        self.assertEqual(self.client.get(SEGMENTS, {"direction": "ailleurs"}).status_code, 400)

    def test_public_without_login(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get(SEGMENTS).status_code, 200)

    def test_single_request_keeps_a_stable_query_count_from_the_cache(self):
        self.segments()
        with self.assertNumQueries(0):
            self.segments()


class SegmentCacheTests(SegmentsTestCase):
    def test_changing_a_fare_refreshes_the_list(self):
        self.assertEqual(self.segments()["segments"][0]["price_fcfa"], 4500)
        admin = User.objects.create_user(username="admin-test", password="secret", role=User.Role.ADMIN)
        self.client.force_authenticate(admin)
        fare = SegmentFare.objects.get(start__location__name="Parakou", end__location__name="Savè")
        self.assertEqual(self.client.patch(f"/api/v1/segment-fares/{fare.pk}/", {"amount": 4700}, format="json").status_code, 200)
        self.assertEqual(self.segments()["segments"][0]["price_fcfa"], 4700)

    def test_changing_a_departure_refreshes_the_list(self):
        self.assertIsNone(self.segments()["segments"][0]["next_departure"])
        trip = self.departure(self.forward)
        self.assertIsNotNone(self.segments()["segments"][0]["next_departure"])
        trip.status = Trip.Status.CANCELLED
        trip.save(update_fields=["status"])
        self.assertIsNone(self.segments()["segments"][0]["next_departure"])


class MissingFareRefusalTests(SegmentsTestCase):
    def setUp(self):
        super().setUp()
        self.trip = self.departure(self.forward)
        # Départ du jour, le seul que le contrôleur peut vendre.
        Trip.objects.filter(pk=self.trip.pk).update(
            departure_at=timezone.make_aware(datetime.combine(timezone.localdate(), time(hour=23, minute=59)))
        )
        self.seat = self.trip.seats.order_by("number").first()
        self.drop_fare("Parakou", "Savè")
        self.segment = {"origin": self.places["Parakou"].pk, "destination": self.places["Savè"].pk}
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)

    def sell(self, role, key):
        user = User.objects.create_user(username=f"test-{key}", password="secret", role=role)
        self.client.force_authenticate(user)
        return self.client.post(
            "/api/v1/staff/sales/sell/",
            {"idempotency_key": key, "trip": self.trip.pk, "seat": self.seat.pk, "passenger_name": "TEST", "payment_method": self.cash.pk, **self.segment},
            format="json",
        )

    def test_search(self):
        self.assert_fare_missing(self.client.get(TRIPS, self.segment))

    def test_search_on_a_date_without_departure(self):
        self.assert_fare_missing(self.client.get(TRIPS, {**self.segment, "date": "2030-01-01"}))

    def test_trip_detail(self):
        self.assert_fare_missing(self.client.get(f"{TRIPS}{self.trip.pk}/", self.segment))

    def test_payment_quotes(self):
        self.assert_fare_missing(self.client.get(f"{TRIPS}{self.trip.pk}/payment-quotes/", self.segment))

    def test_booking(self):
        response = self.client.post(
            "/api/v1/client/bookings/",
            {"trip": self.trip.pk, "contact_phone": "90000000", "passengers": [{"full_name": "TEST", "seat": self.seat.pk}], **self.segment},
            format="json",
        )
        self.assert_fare_missing(response)
        self.assertFalse(Booking.objects.exists())

    def test_counter_sale(self):
        self.assert_fare_missing(self.sell(User.Role.COUNTER, "guichet-tarif-01"))
        self.assertFalse(Booking.objects.exists())

    def test_controller_sale(self):
        self.assert_fare_missing(self.sell(User.Role.CONTROLLER, "controle-tarif-01"))
        self.assertFalse(Booking.objects.exists())

    def test_counter_web_ticket(self):
        user = User.objects.create_user(username="test-guichet-web", password="secret", role=User.Role.COUNTER)
        self.client.force_authenticate(user)
        response = self.client.post(
            "/api/v1/tickets/", {"trip": self.trip.pk, "seat": self.seat.pk, "passenger_name": "TEST", **self.segment}, format="json"
        )
        self.assert_fare_missing(response)
        self.assertFalse(Ticket.objects.exists())

    def test_admin_lists_the_same_missing_fares(self):
        admin = User.objects.create_user(username="admin-test", password="secret", role=User.Role.ADMIN)
        self.client.force_authenticate(admin)
        rows = self.client.get("/api/v1/segment-fares/missing/").json()
        self.assertEqual([(row["origin"], row["destination"]) for row in rows], [("Parakou", "Savè")])

    def test_missing_fares_are_refused_to_a_client(self):
        client = User.objects.create_user(username="client-test", password="secret", role=User.Role.CLIENT)
        self.client.force_authenticate(client)
        self.assertEqual(self.client.get("/api/v1/segment-fares/missing/").status_code, 403)


class SearchVolumeTests(SegmentsTestCase):
    def test_more_than_fifty_departures_on_a_date_all_come_back(self):
        day = timezone.localdate() + timedelta(days=2)
        moment = timezone.make_aware(datetime.combine(day, time(hour=6)))
        Trip.objects.bulk_create(
            Trip(route=self.forward, vehicle=self.vehicle, departure_at=moment + timedelta(minutes=index)) for index in range(55)
        )
        cache.clear()
        response = self.client.get(
            TRIPS,
            {
                "origin": self.places["Parakou"].pk,
                "destination": self.places["Savè"].pk,
                "date": day.isoformat(),
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()["results"]), 55)


class StaffSaleSegmentTests(SegmentsTestCase):
    def setUp(self):
        super().setUp()
        self.trip = self.departure(self.forward)
        Trip.objects.filter(pk=self.trip.pk).update(
            departure_at=timezone.make_aware(datetime.combine(timezone.localdate(), time(hour=23, minute=59)))
        )
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)
        self.controller = User.objects.create_user(username="test-controleur", password="secret", role=User.Role.CONTROLLER)
        self.client.force_authenticate(self.controller)

    def segments_of_trip(self):
        return self.client.get("/api/v1/staff/sales/options/").json()["trips"][0]["segments"]

    def test_controller_sees_all_pairs_in_bus_order_with_server_prices(self):
        rows = self.segments_of_trip()
        self.assertEqual(
            [(row["origin"], row["destination"], int(float(row["quotes"][0]["total"]))) for row in rows],
            [(first, second, GRID[(first, second)]) for first_i, first in enumerate(ORDER) for second in ORDER[first_i + 1:]],
        )

    def test_pair_without_fare_is_not_offered(self):
        self.drop_fare("Savè", "Kétou")
        names = [(row["origin"], row["destination"]) for row in self.segments_of_trip()]
        self.assertEqual(len(names), 9)
        self.assertNotIn(("Savè", "Kétou"), names)

    def test_segment_sale_is_charged_at_the_segment_price(self):
        seat = self.trip.seats.order_by("number").first()
        response = self.client.post(
            "/api/v1/staff/sales/sell/",
            {
                "idempotency_key": "controle-troncon-01",
                "trip": self.trip.pk,
                "seat": seat.pk,
                "passenger_name": "TEST",
                "payment_method": self.cash.pk,
                "origin": str(self.places["Savè"].pk),
                "destination": str(self.places["Kétou"].pk),
            },
            format="json",
        )
        self.assertIn(response.status_code, (200, 201), response.data)
        self.assertEqual(Booking.objects.get().amount, 2500)
