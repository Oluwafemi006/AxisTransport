from datetime import datetime, time, timedelta
from decimal import Decimal
from io import StringIO

from django.core.exceptions import ImproperlyConfigured
from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    Booking,
    FareRule,
    LineStop,
    Location,
    PaymentMethod,
    Route,
    SegmentFare,
    SegmentFareChange,
    SystemSetting,
    Trip,
    User,
    Vehicle,
)
from apps.core.services import generate_trip_seats, reserve_booking, resolve_fare, resolve_segment_fare

FARES = "/api/v1/segment-fares/"
CHANGES = "/api/v1/segment-fare-changes/"
EXPECTED = {
    ("Parakou", "Cotonou"): 7500, ("Parakou", "Bohicon"): 6000, ("Parakou", "Glazoué"): 5000,
    ("Parakou", "Dassa"): 5000, ("Parakou", "Savè"): 3500, ("Savè", "Cotonou"): 6000,
    ("Savè", "Bohicon"): 3000, ("Bohicon", "Cotonou"): 3000,
}


def load():
    call_command("load_segment_fares", stdout=StringIO())


def place(name):
    return Location.objects.get(name=name)


class SegmentFareLoadingTests(APITestCase):
    def test_loads_six_stops_in_line_order_and_eight_fares(self):
        load()
        self.assertEqual(
            [stop.location.name for stop in LineStop.objects.select_related("location")],
            ["Parakou", "Savè", "Glazoué", "Dassa", "Bohicon", "Cotonou"],
        )
        self.assertEqual(SegmentFare.objects.count(), 8)
        for (a, b), amount in EXPECTED.items():
            self.assertEqual(resolve_segment_fare(place(a), place(b)).amount, amount, (a, b))
            self.assertEqual(resolve_segment_fare(place(b), place(a)).amount, amount, (b, a))  # même prix au retour
        self.assertEqual(SegmentFareChange.objects.filter(changed_by__isnull=True, old_amount__isnull=True).count(), 8)

    def test_existing_data_is_untouched_and_no_account_is_created(self):
        parakou = Location.objects.create(name="Parakou", address="Okédama", active=True)
        users = User.objects.count()
        load()
        parakou.refresh_from_db()
        self.assertEqual((parakou.address, parakou.active), ("Okédama", True))
        self.assertEqual(User.objects.count(), users)
        # Les arrêts nouveaux sont créés inactifs : invisibles dans la recherche des clients.
        self.assertFalse(place("Savè").active)
        payload = self.client.get("/api/v1/client/locations/").json()
        names = [item["name"] for item in (payload["results"] if isinstance(payload, dict) else payload)]
        self.assertNotIn("Savè", names)
        self.assertNotIn("Glazoué", names)

    def test_reloading_never_overwrites_a_modified_price(self):
        load()
        fare = resolve_segment_fare(place("Parakou"), place("Savè"))
        SegmentFare.objects.filter(pk=fare.pk).update(amount=5000)
        load()
        fare.refresh_from_db()
        self.assertEqual(fare.amount, 5000)
        self.assertEqual(SegmentFare.objects.count(), 8)

    def test_pair_without_price_is_not_sellable(self):
        load()
        pair = SegmentFare.objects.filter(start__location__name="Savè", end__location__name="Bohicon")
        SegmentFareChange.objects.filter(fare__in=pair).delete()
        pair.delete()
        with self.assertRaises(ImproperlyConfigured):
            resolve_segment_fare(place("Bohicon"), place("Savè"))
        other = Location.objects.create(name="Ville hors ligne")
        with self.assertRaises(ImproperlyConfigured):
            resolve_segment_fare(place("Parakou"), other)
        with self.assertRaises(ImproperlyConfigured):
            resolve_segment_fare(place("Parakou"), place("Parakou"))


class SegmentFareAdminApiTests(APITestCase):
    def setUp(self):
        load()
        self.admin = User.objects.create_user(username="admin", password="secret", role=User.Role.ADMIN, first_name="Adèle")
        self.fare = resolve_segment_fare(place("Parakou"), place("Savè"))
        self.url = f"{FARES}{self.fare.pk}/"
        self.client.force_authenticate(self.admin)

    def test_admin_lists_the_eight_pairs_in_line_order(self):
        rows = self.client.get(FARES).json()
        self.assertEqual(len(rows), 8)
        self.assertEqual(rows[0]["label"], "Parakou ↔ Savè")
        self.assertEqual(rows[0]["amount"], 3500)
        positions = [(row["start_position"], row["end_position"]) for row in rows]
        self.assertEqual(positions, sorted(positions))

    def test_only_admin_reads_or_changes_prices(self):
        others = [
            User.objects.create_user(username=f"u{role}", password="secret", role=role)
            for role in (User.Role.COUNTER, User.Role.CONTROLLER, User.Role.CLIENT)
        ]
        for user in others:
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get(FARES).status_code, 403, user.role)
            self.assertEqual(self.client.patch(self.url, {"amount": 1}, format="json").status_code, 403, user.role)
            self.assertEqual(self.client.get(CHANGES).status_code, 403, user.role)
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get(FARES).status_code, 401)
        self.assertEqual(self.client.get(CHANGES).status_code, 401)
        self.fare.refresh_from_db()
        self.assertEqual(self.fare.amount, 3500)

    def test_change_is_visible_at_once_and_logged(self):
        response = self.client.patch(self.url, {"amount": "5 000"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual((response.data["amount"], response.data["changed"]), (5000, True))
        # Relecture immédiate : aucune valeur périmée, ni par l'API, ni par le calcul du prix.
        row = next(item for item in self.client.get(FARES).json() if item["id"] == self.fare.pk)
        self.assertEqual(row["amount"], 5000)
        self.assertEqual(row["updated_by_name"], "Adèle")
        self.assertEqual(resolve_segment_fare(place("Savè"), place("Parakou")).amount, 5000)
        entry = self.client.get(CHANGES).json()["results"][0]
        self.assertEqual(
            (entry["label"], entry["old_amount"], entry["new_amount"], entry["changed_by_name"]),
            ("Parakou ↔ Savè", 3500, 5000, "Adèle"),
        )

    def test_same_price_is_not_logged(self):
        response = self.client.patch(self.url, {"amount": 3500}, format="json")
        self.assertEqual((response.status_code, response.data["changed"]), (200, False))
        self.assertEqual(SegmentFareChange.objects.filter(changed_by=self.admin).count(), 0)

    def test_invalid_prices_are_refused_with_a_clear_message(self):
        for value in (0, -5, "abc", "7500.5", "7,5", "", None, True, 99999999999):
            response = self.client.patch(self.url, {"amount": value}, format="json")
            self.assertEqual(response.status_code, 400, value)
            self.assertIn("amount", response.data)
        self.fare.refresh_from_db()
        self.assertEqual(self.fare.amount, 3500)
        self.assertEqual(SegmentFareChange.objects.filter(changed_by=self.admin).count(), 0)

    def test_only_the_price_can_change_and_pairs_cannot_be_created_or_deleted(self):
        self.assertEqual(self.client.patch(self.url, {"amount": 5000, "currency": "EUR"}, format="json").status_code, 400)
        self.assertEqual(self.client.put(self.url, {"amount": 5000}, format="json").status_code, 405)
        self.assertEqual(self.client.post(FARES, {"amount": 1000}, format="json").status_code, 405)
        self.assertEqual(self.client.delete(self.url).status_code, 405)
        self.assertEqual(self.client.post(CHANGES, {}, format="json").status_code, 405)
        self.assertEqual(SegmentFare.objects.count(), 8)


class FullTripPricedByGridTests(APITestCase):
    """Le trajet entier se vend au prix du tronçon de la grille ; la règle du parcours (gardée) ne fixe plus le prix."""

    def setUp(self):
        load()
        # Les terminus sont actifs en service (créés par bootstrap_axis) ; la grille seule les crée inactifs.
        Location.objects.filter(name__in=["Parakou", "Cotonou"]).update(active=True)
        parakou, cotonou = place("Parakou"), place("Cotonou")
        route = Route.objects.create(origin=parakou, destination=cotonou)
        FareRule.objects.create(route=route, name="Standard", amount=Decimal("5000"))  # ignorée pour le prix
        vehicle = Vehicle.objects.create(category=Vehicle.Category.BUS, name="Yutong", capacity=4)
        departure = timezone.make_aware(datetime.combine(timezone.localdate() + timedelta(days=1), time(8)))
        self.trip = Trip.objects.create(route=route, vehicle=vehicle, departure_at=departure)
        generate_trip_seats(self.trip)
        SystemSetting.objects.create(key="ticket_hold_minutes", value=10)
        PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)

    def test_full_trip_sells_at_its_grid_price(self):
        self.assertEqual(resolve_fare(self.trip).amount, Decimal("5000"))  # code de la règle gardé, non utilisé
        quote = self.client.get(f"/api/v1/client/trips/{self.trip.pk}/payment-quotes/").json()[0]
        self.assertEqual(Decimal(str(quote["amount"])), Decimal("7500"))

    def test_existing_booking_keeps_its_price_after_a_grid_change(self):
        booking, _ = reserve_booking(trip=self.trip, passengers=[{"full_name": "Awa", "seat": self.trip.seats.first()}])
        admin = User.objects.create_user(username="admin", password="secret", role=User.Role.ADMIN)
        self.client.force_authenticate(admin)
        fare = resolve_segment_fare(place("Parakou"), place("Cotonou"))
        self.assertEqual(self.client.patch(f"{FARES}{fare.pk}/", {"amount": 9000}, format="json").status_code, 200)
        booking.refresh_from_db()
        self.assertEqual(booking.amount, Decimal("7500"))
        self.assertEqual(booking.tickets.get().amount, Decimal("7500"))
        self.assertEqual(Booking.objects.count(), 1)

    def test_grid_is_not_exposed_to_clients(self):
        self.client.force_authenticate(User.objects.create_user(username="c", password="s", role=User.Role.CLIENT))
        self.assertEqual(self.client.get(FARES).status_code, 403)
        self.assertEqual(self.client.get("/api/v1/client/segment-fares/").status_code, 404)
        trip = self.client.get(f"/api/v1/client/trips/{self.trip.pk}/").json()
        self.assertNotIn("segment", str(trip).lower())
