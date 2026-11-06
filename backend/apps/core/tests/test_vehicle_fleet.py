"""Flotte de location gérée depuis /admin : champs, photo (Cloudinary), indisponible, archivage, demandes refusées."""
import io
import json
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from PIL import Image
from rest_framework.test import APITestCase

from apps.core import photo_storage
from apps.core.models import RentalBooking, User, Vehicle

from .factories import build_operational_context

VEHICLES = "/api/v1/vehicles/"
PUBLIC = "/api/v1/client/vehicles/"
RENTALS = "/api/v1/client/rentals/"


def image_file(fmt="PNG", size=(2400, 1200), name="TEST.png"):
    buffer = io.BytesIO()
    Image.new("RGB", size, (10, 120, 200)).save(buffer, format=fmt)
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/png")


class VehicleFleetTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.admin = self.context["admin"]
        self.car = Vehicle.objects.create(
            category=Vehicle.Category.RENTAL, name="TEST voiture", capacity=4,
            rental_daily_rate=Decimal("20000"), state=Vehicle.State.ACTIVE,
        )

    def test_admin_adds_and_edits_a_vehicle_with_new_fields(self):
        self.client.force_authenticate(self.admin)
        created = self.client.post(VEHICLES, {
            "category": "RENTAL", "name": "TEST 4x4", "capacity": 5, "brand": "TEST marque", "model_name": "TEST modèle",
            "transmission": "AUTOMATIC", "fuel": "DIESEL", "rental_daily_rate": "30000",
            "rental_daily_rate_with_driver": "40000", "driver_available": True, "driver_required": True,
        }, format="json")
        self.assertEqual(created.status_code, 201, created.data)
        vehicle = Vehicle.objects.get(pk=created.data["id"])
        self.assertEqual((vehicle.fuel, vehicle.transmission, vehicle.driver_required), ("DIESEL", "AUTOMATIC", True))
        edited = self.client.patch(f"{VEHICLES}{vehicle.pk}/", {"fuel": "HYBRID"}, format="json")
        self.assertEqual(edited.status_code, 200, edited.data)
        # « Avec chauffeur uniquement » sans chauffeur disponible : refusé.
        refused = self.client.patch(f"{VEHICLES}{vehicle.pk}/", {"driver_available": False}, format="json")
        self.assertEqual(refused.status_code, 400)

    def test_non_admin_cannot_add_edit_archive_or_send_a_photo(self):
        counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        for user in (counter, self.context["controller"], self.context["client"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.post(VEHICLES, {"category": "RENTAL", "name": "TEST"}, format="json").status_code, 403)
            self.assertEqual(self.client.patch(f"{VEHICLES}{self.car.pk}/", {"archived": True}, format="json").status_code, 403)
            response = self.client.post(f"{VEHICLES}{self.car.pk}/photo/", {"photo": image_file()}, format="multipart")
            self.assertEqual(response.status_code, 403)

    def test_photo_is_checked_resized_and_sent_to_the_vehicle_folder(self):
        self.client.force_authenticate(self.admin)
        sent = {}

        def fake_upload(photo, *, folder):
            sent["folder"] = folder
            sent["image"] = Image.open(io.BytesIO(photo.read()))
            return "https://test.invalid/vehicule.jpg", "TEST-public-id"

        with mock.patch("apps.core.views.upload_photo", side_effect=fake_upload):
            response = self.client.post(f"{VEHICLES}{self.car.pk}/photo/", {"photo": image_file()}, format="multipart")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(sent["folder"], photo_storage.VEHICLE_FOLDER)
        self.assertEqual(sent["image"].format, "JPEG")
        self.assertLessEqual(max(sent["image"].size), 1600)
        self.car.refresh_from_db()
        self.assertEqual(self.car.photo_url, "https://test.invalid/vehicule.jpg")

    def test_non_image_and_unsupported_formats_are_refused(self):
        self.client.force_authenticate(self.admin)
        fake = SimpleUploadedFile("TEST.jpg", b"pas une image TEST", content_type="image/jpeg")
        with mock.patch("apps.core.views.upload_photo") as upload:
            response = self.client.post(f"{VEHICLES}{self.car.pk}/photo/", {"photo": fake}, format="multipart")
            self.assertEqual(response.status_code, 400)
            gif = self.client.post(f"{VEHICLES}{self.car.pk}/photo/", {"photo": image_file("GIF", (40, 40), "TEST.gif")}, format="multipart")
            self.assertEqual(gif.status_code, 400)
            upload.assert_not_called()

    def test_photo_too_large_is_refused(self):
        big = mock.Mock(size=photo_storage.MAX_PHOTO_BYTES + 1)
        with self.assertRaises(Exception):
            photo_storage.prepare_vehicle_photo(big)

    def test_public_list_shows_unavailable_and_hides_archived(self):
        unavailable = Vehicle.objects.create(category="RENTAL", name="TEST panne", state=Vehicle.State.MAINTENANCE)
        archived = Vehicle.objects.create(category="RENTAL", name="TEST archivé", archived=True)
        payload = self.client.get(PUBLIC).json()
        items = payload["results"] if isinstance(payload, dict) else payload
        by_id = {row["id"]: row for row in items}
        self.assertTrue(by_id[self.car.pk]["rentable"])
        self.assertFalse(by_id[unavailable.pk]["rentable"])
        self.assertNotIn(archived.pk, by_id)
        public = self.client.get(VEHICLES).json()
        public_items = public["results"] if isinstance(public, dict) else public
        self.assertNotIn(archived.pk, {row["id"] for row in public_items})

    def ask(self, vehicle, **extra):
        self.client.force_authenticate(self.context["client"])
        start = timezone.now() + timedelta(days=3)
        return self.client.post(RENTALS, {
            "vehicle": vehicle.pk, "starts_at": start.isoformat(), "ends_at": (start + timedelta(days=1)).isoformat(), **extra,
        }, format="json")

    def test_rental_request_accepted_only_for_an_active_unarchived_vehicle(self):
        self.assertEqual(self.ask(self.car).status_code, 201)
        down = Vehicle.objects.create(category="RENTAL", name="TEST indispo", state=Vehicle.State.UNAVAILABLE)
        refused = self.ask(down)
        self.assertEqual(refused.status_code, 400)
        self.assertIn("indisponible", str(refused.data))
        old = Vehicle.objects.create(category="RENTAL", name="TEST archivé", archived=True)
        self.assertEqual(self.ask(old).status_code, 400)
        self.assertEqual(RentalBooking.objects.count(), 1)

    def test_driver_only_vehicle_requires_a_driver(self):
        Vehicle.objects.filter(pk=self.car.pk).update(driver_available=True, driver_required=True)
        self.assertEqual(self.ask(self.car).status_code, 400)
        self.assertEqual(self.ask(self.car, with_driver=True).status_code, 201)

    def test_vehicle_with_history_is_archived_not_deleted(self):
        self.assertEqual(self.ask(self.car).status_code, 201)
        self.client.force_authenticate(self.admin)
        response = self.client.delete(f"{VEHICLES}{self.car.pk}/")
        self.assertEqual(response.status_code, 400)
        self.assertTrue(Vehicle.objects.filter(pk=self.car.pk).exists())
        archived = self.client.patch(f"{VEHICLES}{self.car.pk}/", {"archived": True}, format="json")
        self.assertEqual(archived.status_code, 200)
        unused = Vehicle.objects.create(category="RENTAL", name="TEST jamais utilisé")
        self.assertEqual(self.client.delete(f"{VEHICLES}{unused.pk}/").status_code, 204)


@override_settings(CLOUDINARY_CLOUD_NAME="TEST-cloud", CLOUDINARY_API_KEY="TEST-key", CLOUDINARY_API_SECRET="TEST-secret")
class PhotoStorageFolderTests(APITestCase):
    """Le partage du code d'envoi ne change rien aux photos de colis : même dossier, même réponse."""

    def upload(self, func, *args, **kwargs):
        captured = {}

        class _Response(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

        def fake_urlopen(request, timeout):
            captured["body"] = request.data
            return _Response(json.dumps({"secure_url": "https://test.invalid/x.jpg", "public_id": "TEST"}).encode())

        with mock.patch("apps.core.photo_storage.urllib.request.urlopen", side_effect=fake_urlopen):
            result = func(*args, **kwargs)
        return result, captured["body"]

    def test_parcel_photo_still_goes_to_the_parcel_folder(self):
        photo = SimpleUploadedFile("colis.jpg", b"TEST-octets", content_type="image/jpeg")
        result, body = self.upload(photo_storage.upload_parcel_photo, photo)
        self.assertEqual(result, ("https://test.invalid/x.jpg", "TEST"))
        self.assertIn(b"axis/colis", body)
        self.assertIn(b"TEST-octets", body)

    def test_vehicle_photo_goes_to_the_vehicle_folder(self):
        prepared = photo_storage.prepare_vehicle_photo(image_file())
        _, body = self.upload(photo_storage.upload_photo, prepared, folder=photo_storage.VEHICLE_FOLDER)
        self.assertIn(b"axis/vehicules", body)
