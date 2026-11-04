"""Locations gérées par l'admin : statut, montants, motif d'annulation, journal, conflit de période."""
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import RentalBooking, RentalChange, User, Vehicle

from .factories import build_operational_context


class RentalAdminTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.car = Vehicle.objects.create(
            category=Vehicle.Category.RENTAL, name="TEST voiture", capacity=4, rental_daily_rate=Decimal("20000")
        )
        start = timezone.now() + timedelta(days=2)
        self.rental = RentalBooking.objects.create(
            vehicle=self.car, customer=self.context["client"], starts_at=start, ends_at=start + timedelta(days=1)
        )
        self.url = f"/api/v1/rentals/{self.rental.pk}/manage/"
        self.client.force_authenticate(self.context["admin"])

    def test_confirm_with_amounts_is_logged(self):
        response = self.client.post(self.url, {"status": "CONFIRMED", "total_amount": 20000, "deposit_amount": 50000}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.rental.refresh_from_db()
        self.assertEqual((self.rental.status, int(self.rental.total_amount)), ("CONFIRMED", 20000))
        self.assertEqual(RentalChange.objects.count(), 1)
        self.assertEqual(len(self.client.get("/api/v1/rentals/changes/").json()), 1)

    def test_forbidden_jump_and_cancel_without_reason(self):
        self.assertEqual(self.client.post(self.url, {"status": "COMPLETED"}, format="json").status_code, 400)
        self.assertEqual(self.client.post(self.url, {"status": "CANCELLED"}, format="json").status_code, 400)
        self.assertEqual(self.client.post(self.url, {"status": "CANCELLED", "note": "Client TEST"}, format="json").status_code, 200)

    def test_overlapping_rental_cannot_be_confirmed(self):
        RentalBooking.objects.create(
            vehicle=self.car, customer=self.context["client"], starts_at=self.rental.starts_at,
            ends_at=self.rental.ends_at, status=RentalBooking.Status.CONFIRMED,
        )
        self.assertEqual(self.client.post(self.url, {"status": "CONFIRMED"}, format="json").status_code, 400)

    def test_only_admin_manages_and_nobody_deletes(self):
        self.assertEqual(self.client.delete(f"/api/v1/rentals/{self.rental.pk}/").status_code, 405)
        counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        # Refusé : le guichet ne voit aucune location (404) ou n'a pas le droit (403).
        self.assertIn(self.client.post(self.url, {"status": "CONFIRMED"}, format="json").status_code, {403, 404})
