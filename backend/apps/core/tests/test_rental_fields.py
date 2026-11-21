"""Location : champs obligatoires, zones gérées dans l'admin, guichet (consultation + demande pour un client présent), permissions."""
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.account_deletion import delete_client_account
from apps.core.models import RentalBooking, RentalChange, RentalZone, User, Vehicle

from .factories import build_operational_context

PASSWORD = "TEST-mot-de-passe-42"


class RentalFieldsTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.client_user = self.context["client"]
        User.objects.filter(pk=self.client_user.pk).update(phone="+2290100000009")
        self.client_user.refresh_from_db()
        self.car = Vehicle.objects.create(category=Vehicle.Category.RENTAL, name="TEST voiture", capacity=5, rental_daily_rate=Decimal("1000"))
        self.zone = RentalZone.objects.create(name="Zone TEST")
        self.closed_zone = RentalZone.objects.create(name="Zone fermée TEST", active=False)
        self.counter = User.objects.create_user(username="guichet-location-test", password=PASSWORD, role=User.Role.COUNTER)
        start = timezone.now() + timedelta(days=3)
        self.payload = {
            "vehicle": self.car.id, "starts_at": start.isoformat(), "ends_at": (start + timedelta(days=2)).isoformat(),
            "with_driver": False, "renter_full_name": "Locataire TEST", "cip_number": "CIP-TEST-1",
            "licence_number": "PERMIS-TEST-1", "zone": self.zone.id,
        }

    def test_client_request_with_all_fields(self):
        self.client.force_authenticate(self.client_user)
        response = self.client.post("/api/v1/client/rentals/", self.payload, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["zone_name"], "Zone TEST")

    def test_missing_fields_are_refused_in_french(self):
        self.client.force_authenticate(self.client_user)
        for field in ("renter_full_name", "cip_number", "licence_number", "zone"):
            with self.subTest(field=field):
                data = {**self.payload, field: "" if field != "zone" else None}
                response = self.client.post("/api/v1/client/rentals/", data, format="json")
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.data)
        response = self.client.post("/api/v1/client/rentals/", {**self.payload, "zone": self.closed_zone.id}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_zones_listed_active_only_and_managed_by_admin(self):
        self.assertEqual([z["name"] for z in self.client.get("/api/v1/rental-zones/").json()["results"]], ["Zone TEST"])
        self.client.force_authenticate(self.counter)
        self.assertEqual(self.client.post("/api/v1/rental-zones/", {"name": "Autre TEST"}).status_code, 403)
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(self.client.post("/api/v1/rental-zones/", {"name": "Autre TEST"}).status_code, 201)
        self.assertEqual(len(self.client.get("/api/v1/rental-zones/", {"all": "true"}).json()["results"]), 3)

    def test_counter_records_for_a_present_client_and_can_only_read(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post("/api/v1/rentals/counter/", {**self.payload, "customer_phone": "01 00 00 00 09"}, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        rental = RentalBooking.objects.get()
        self.assertEqual(rental.customer, self.client_user)
        self.assertEqual(RentalChange.objects.get().actor, self.counter)
        self.assertEqual(len(self.client.get("/api/v1/rentals/").json()["results"]), 1)
        # Ni gestion (statut, montants), ni modification, ni véhicules.
        self.assertEqual(self.client.post(f"/api/v1/rentals/{rental.id}/manage/", {"status": "CONFIRMED"}, format="json").status_code, 403)
        self.assertEqual(self.client.patch(f"/api/v1/rentals/{rental.id}/", {"with_driver": True}, format="json").status_code, 403)
        self.assertEqual(self.client.patch(f"/api/v1/vehicles/{self.car.id}/", {"rental_daily_rate": 1}, format="json").status_code, 403)

    def test_counter_needs_a_known_client_phone(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post("/api/v1/rentals/counter/", {**self.payload, "customer_phone": "0100000001"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("inscrit", str(response.data))

    def test_client_cannot_manage_or_read_the_log(self):
        self.client.force_authenticate(self.client_user)
        rental = RentalBooking.objects.create(vehicle=self.car, customer=self.client_user,
                                              starts_at=timezone.now() + timedelta(days=5), ends_at=timezone.now() + timedelta(days=6))
        self.assertEqual(self.client.post(f"/api/v1/rentals/{rental.id}/manage/", {"status": "CONFIRMED"}, format="json").status_code, 403)
        self.assertEqual(self.client.get("/api/v1/rentals/changes/").status_code, 403)
        self.assertEqual(self.client.post("/api/v1/rentals/counter/", {**self.payload, "customer_phone": "0100000009"}, format="json").status_code, 403)

    def test_account_deletion_blanks_the_new_fields(self):
        self.client_user.set_password(PASSWORD)
        self.client_user.save()
        rental = RentalBooking.objects.create(vehicle=self.car, customer=self.client_user, status=RentalBooking.Status.COMPLETED,
                                              starts_at=timezone.now() - timedelta(days=5), ends_at=timezone.now() - timedelta(days=4),
                                              renter_full_name="Locataire TEST", cip_number="CIP-TEST", licence_number="PERMIS-TEST", zone=self.zone)
        delete_client_account(self.client_user, PASSWORD)
        rental.refresh_from_db()
        self.assertEqual((rental.cip_number, rental.licence_number), ("", ""))
        self.assertNotIn("TEST", rental.renter_full_name)
        self.assertEqual(rental.zone, self.zone)
