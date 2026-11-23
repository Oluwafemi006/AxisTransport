"""Durcissement : guichet sans liste complète, fichiers de location non envoyables, réglages HTTPS."""
from datetime import timedelta
from decimal import Decimal

from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Parcel, RentalBooking, RentalZone, User, Vehicle

from .factories import build_operational_context, rental_identity
from .test_payment_security import make_booking


class CounterListsTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.counter = User.objects.create_user(username="guichet-durci-test", password="TEST-x", role=User.Role.COUNTER)
        self.client.force_authenticate(self.counter)

    def rows(self, url):
        data = self.client.get(url).json()
        return data["results"] if isinstance(data, dict) else data

    def test_counter_cannot_list_every_ticket_but_admin_can(self):
        make_booking(self.context, seats=1)
        self.assertEqual(self.rows("/api/v1/tickets/"), [])
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(len(self.rows("/api/v1/tickets/")), 1)

    def test_counter_sees_only_open_parcels(self):
        route = self.context["trip"].route
        common = dict(sender_name="Exp TEST", sender_phone="0100000009", recipient_name="Dest TEST",
                      recipient_phone="0100000008", origin=route.origin, destination=route.destination, description="TEST")
        open_one = Parcel.objects.create(**common)
        done = Parcel.objects.create(**common)
        Parcel.objects.filter(pk=done.pk).update(status=Parcel.Status.PICKED_UP)
        self.assertEqual([row["id"] for row in self.rows("/api/v1/parcels/")], [open_one.id])

    def test_counter_sees_open_rentals_with_masked_documents(self):
        car = Vehicle.objects.create(category=Vehicle.Category.RENTAL, name="TEST voiture", capacity=4, rental_daily_rate=Decimal("1000"))
        zone = RentalZone.objects.create(name="Zone durci TEST")
        start = timezone.now() + timedelta(days=3)
        base = dict(vehicle=car, customer=self.context["client"], zone=zone, renter_full_name="Locataire TEST")
        open_rental = RentalBooking.objects.create(starts_at=start, ends_at=start + timedelta(days=1), cip_number="CIP123456", licence_number="PER987654", **base)
        RentalBooking.objects.create(starts_at=start + timedelta(days=10), ends_at=start + timedelta(days=11), status=RentalBooking.Status.COMPLETED, **base)
        rows = self.rows("/api/v1/rentals/")
        self.assertEqual([row["id"] for row in rows], [open_rental.id])
        self.assertEqual((rows[0]["cip_number"], rows[0]["licence_number"]), ("•••456", "•••654"))
        self.client.force_authenticate(self.context["admin"])
        admin_rows = {row["id"]: row for row in self.rows("/api/v1/rentals/")}
        self.assertEqual(admin_rows[open_rental.id]["cip_number"], "CIP123456")


class RentalFilesTests(APITestCase):
    def test_client_cannot_upload_documents_with_a_request(self):
        context = build_operational_context()
        car = Vehicle.objects.create(category=Vehicle.Category.RENTAL, name="TEST voiture", capacity=4, rental_daily_rate=Decimal("1000"))
        self.client.force_authenticate(context["client"])
        start = timezone.now() + timedelta(days=3)
        response = self.client.post("/api/v1/client/rentals/", {
            "vehicle": car.pk, "starts_at": start.isoformat(), "ends_at": (start + timedelta(days=1)).isoformat(),
            **rental_identity(), "identity_document": SimpleUploadedFile("TEST.bin", b"0" * 1024),
        }, format="multipart")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertFalse(RentalBooking.objects.get().identity_document)
