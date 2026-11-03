from datetime import datetime, time, timedelta
from io import StringIO
from unittest import mock

from django.core.cache import cache
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    Booking,
    LineStop,
    Location,
    Parcel,
    ParcelPhoto,
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
ORDER = ["Parakou", "Savè", "Glazoué", "Dassa", "Bohicon", "Cotonou"]
GRID = {
    ("Parakou", "Cotonou"): 7500, ("Parakou", "Bohicon"): 6000, ("Parakou", "Glazoué"): 5000, ("Parakou", "Dassa"): 5000,
    ("Parakou", "Savè"): 3500, ("Savè", "Cotonou"): 6000, ("Savè", "Bohicon"): 3000, ("Bohicon", "Cotonou"): 3000,
}


def priced_pairs(order):
    """Paires dans l'ordre du bus qui ont un tarif (le même dans les deux sens) ; les autres ne sont pas vendables."""
    rows = []
    for index, first in enumerate(order):
        for second in order[index + 1:]:
            amount = GRID.get((first, second), GRID.get((second, first)))
            if amount is not None:
                rows.append((first, second, amount))
    return rows


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
    def test_priced_pairs_in_stop_order_on_the_way_out(self):
        rows = self.segments()["segments"]
        self.assertEqual(
            [(row["origin"], row["destination"], row["price_fcfa"]) for row in rows],
            priced_pairs(ORDER),
        )

    def test_priced_pairs_in_stop_order_with_the_same_prices_on_the_way_back(self):
        rows = self.segments("retour")["segments"]
        back = ORDER[::-1]
        self.assertEqual(
            [(row["origin"], row["destination"], row["price_fcfa"]) for row in rows],
            priced_pairs(back),
        )

    def test_pair_without_fare_is_listed_in_missing_fares_only(self):
        self.drop_fare("Savè", "Bohicon")
        payload = self.segments()
        self.assertEqual(len(payload["segments"]), 7)
        self.assertNotIn(("Savè", "Bohicon"), [(row["origin"], row["destination"]) for row in payload["segments"]])
        missing = [(row["origin"], row["destination"]) for row in payload["missing_fares"]]
        self.assertIn(("Savè", "Bohicon"), missing)
        # Tronçons sans tarif (validé par le boss) : jamais vendables.
        for pair in (("Savè", "Glazoué"), ("Savè", "Dassa"), ("Glazoué", "Dassa"), ("Glazoué", "Cotonou"), ("Dassa", "Bohicon")):
            self.assertIn(pair, missing)

    def test_inactive_stop_gives_no_pair(self):
        Location.objects.filter(name="Glazoué").update(active=False)
        cache.clear()
        names = {row["origin"] for row in self.segments()["segments"]} | {row["destination"] for row in self.segments()["segments"]}
        self.assertNotIn("Glazoué", names)

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
        self.assertEqual(self.segments()["segments"][0]["price_fcfa"], 3500)
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
        self.assertIn(("Parakou", "Savè"), [(row["origin"], row["destination"]) for row in rows])

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
            priced_pairs(ORDER),
        )

    def test_pair_without_fare_is_not_offered(self):
        self.drop_fare("Savè", "Bohicon")
        names = [(row["origin"], row["destination"]) for row in self.segments_of_trip()]
        self.assertEqual(len(names), 7)
        self.assertNotIn(("Savè", "Bohicon"), names)

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
                "destination": str(self.places["Bohicon"].pk),
            },
            format="json",
        )
        self.assertIn(response.status_code, (200, 201), response.data)
        self.assertEqual(Booking.objects.get().amount, 3000)

    def test_day_summary_counts_the_sale_of_this_agent(self):
        self.test_segment_sale_is_charged_at_the_segment_price()
        body = self.client.get("/api/v1/staff/sales/summary/").json()
        self.assertEqual(
            body, {"scanned_tickets": 0, "sold_tickets": 1, "parcels": 0, "cash_fcfa": 3000, "mobile_money_fcfa": 0}
        )
        other = User.objects.create_user(username="test-autre", password="secret", role=User.Role.CONTROLLER)
        self.client.force_authenticate(other)
        self.assertEqual(self.client.get("/api/v1/staff/sales/summary/").json()["sold_tickets"], 0)

    def arrive(self, name):
        return self.client.post(
            "/api/v1/staff/sales/arrival/", {"trip": self.trip.pk, "stop": self.places[name].pk}, format="json"
        )

    def test_intermediate_stop_can_be_skipped_and_final_ends_the_trip(self):
        self.assertEqual(self.arrive("Dassa").status_code, 200)
        self.trip.refresh_from_db()
        self.assertEqual(self.trip.status, Trip.Status.SCHEDULED)
        self.assertEqual(self.arrive("Cotonou").status_code, 200)
        self.trip.refresh_from_db()
        self.assertEqual(self.trip.status, Trip.Status.COMPLETED)

    def test_first_stop_is_not_an_arrival(self):
        self.assertEqual(self.arrive("Parakou").status_code, 400)

    def test_agency_sees_the_position_and_a_client_cannot(self):
        self.arrive("Savè")
        admin = User.objects.create_user(username="test-admin", password="secret", role=User.Role.ADMIN)
        self.client.force_authenticate(admin)
        rows = self.client.get("/api/v1/bus-positions/").json()
        self.assertEqual((rows[0]["stop"], rows[0]["final"]), ("Savè", False))
        client = User.objects.create_user(username="test-client", password="secret", role=User.Role.CLIENT)
        self.client.force_authenticate(client)
        self.assertEqual(self.client.get("/api/v1/bus-positions/").status_code, 403)

    def post_parcel(self, photos=1):
        files = [SimpleUploadedFile(f"test{index}.jpg", b"TEST", content_type="image/jpeg") for index in range(photos)]
        return self.client.post(
            "/api/v1/staff/sales/parcel/",
            {
                "sender_name": "TEST exp", "sender_phone": "90000000", "recipient_name": "TEST dest",
                "recipient_phone": "90000001", "origin": self.places["Parakou"].pk,
                "destination": self.places["Savè"].pk, "description": "TEST colis", "photos": files,
            },
            format="multipart",
        )

    def test_parcel_needs_a_photo(self):
        self.assertEqual(self.post_parcel(photos=0).status_code, 400)

    def test_parcel_is_saved_with_its_photos_and_counted(self):
        with mock.patch("apps.core.views.upload_parcel_photo", return_value=("https://test.invalid/a.jpg", "TEST")):
            response = self.post_parcel(photos=2)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(ParcelPhoto.objects.count(), 2)
        self.assertEqual(self.client.get("/api/v1/staff/sales/summary/").json()["parcels"], 1)

    def test_failed_upload_saves_nothing(self):
        with mock.patch("apps.core.views.upload_parcel_photo", side_effect=DjangoValidationError("TEST échec")):
            self.assertEqual(self.post_parcel().status_code, 400)
        self.assertFalse(Parcel.objects.exists())

    def test_parcel_takes_the_base_price_then_the_agency_can_change_it(self):
        SystemSetting.objects.create(key="parcel_base_price_fcfa", value=2000)
        with mock.patch("apps.core.views.upload_parcel_photo", return_value=("https://test.invalid/a.jpg", "TEST")):
            self.post_parcel()
        parcel = Parcel.objects.get()
        self.assertEqual(parcel.amount, 2000)
        self.assertEqual(self.client.post(f"/api/v1/parcels/{parcel.pk}/price/", {"amount": 5000}).status_code, 403)
        counter = User.objects.create_user(username="test-guichet", password="secret", role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        self.assertEqual(self.client.post(f"/api/v1/parcels/{parcel.pk}/price/", {"amount": 5000}).status_code, 200)
        parcel.refresh_from_db()
        self.assertEqual(parcel.amount, 5000)

    def test_controller_lists_his_parcels_and_client_sees_the_photo(self):
        with mock.patch("apps.core.views.upload_parcel_photo", return_value=("https://test.invalid/a.jpg", "TEST")):
            code = self.post_parcel().data["tracking_number"]
        rows = self.client.get("/api/v1/staff/sales/parcels/").json()
        self.assertEqual([row["tracking_number"] for row in rows], [code])
        self.client.force_authenticate(None)
        body = self.client.get("/api/v1/client/parcels/track/", {"code": code}).json()
        self.assertEqual(body["photos"], ["https://test.invalid/a.jpg"])
        self.assertNotIn("sender_name", body)

    def test_options_give_the_real_parcel_price_before_validation(self):
        SystemSetting.objects.create(key="parcel_base_price_fcfa", value=2000)
        self.assertEqual(self.client.get("/api/v1/staff/sales/options/").json()["parcel_base_fcfa"], 2000)
