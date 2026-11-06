"""Demande de location envoyée depuis le site : même adresse et même corps que l'application."""
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import RentalBooking, Vehicle

from .factories import build_operational_context

RENTALS = "/api/v1/client/rentals/"


class SiteRentalRequestTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.car = Vehicle.objects.create(
            category=Vehicle.Category.RENTAL, name="TEST voiture site", capacity=4,
            rental_daily_rate=Decimal("20000"), state=Vehicle.State.ACTIVE,
        )
        start = timezone.now() + timedelta(days=2)
        # Corps construit par rentalRequestBody (portal-rules.ts), identique à createRental (api_client.dart).
        self.body = {"vehicle": self.car.pk, "starts_at": start.isoformat(), "ends_at": (start + timedelta(days=1)).isoformat(), "with_driver": False}

    def test_visitor_without_account_is_refused_and_nothing_is_created(self):
        response = self.client.post(RENTALS, self.body, format="json")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(RentalBooking.objects.count(), 0)

    def test_staff_account_cannot_request_a_rental(self):
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(self.client.post(RENTALS, self.body, format="json").status_code, 403)

    def test_client_request_is_created_as_requested_without_amount(self):
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(RENTALS, self.body, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "REQUESTED")
        self.assertIsNone(response.data["total_amount"])
        # Visible dans /admin, onglet « Locations » (liste /rentals/ de l'admin).
        self.client.force_authenticate(self.context["admin"])
        rows = self.client.get("/api/v1/rentals/").json()
        rows = rows["results"] if isinstance(rows, dict) else rows
        self.assertIn(response.data["id"], [row["id"] for row in rows])
