"""Lien Google Maps des points d'embarquement : saisi dans l'admin, https et domaines Google Maps seulement."""
from rest_framework.test import APITestCase

from apps.core.models import BoardingPoint

from .factories import build_operational_context

URL = "/api/v1/boarding-points/"


class BoardingMapUrlTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.point = BoardingPoint.objects.create(location=self.context["trip"].route.origin, name="Gare TEST")
        self.client.force_authenticate(self.context["admin"])

    def patch(self, value):
        return self.client.patch(f"{URL}{self.point.pk}/", {"map_url": value}, format="json")

    def test_google_maps_links_are_accepted(self):
        for value in ("https://maps.app.goo.gl/TEST", "https://share.google/TEST", "https://www.google.com/maps/place/TEST", "https://google.com/maps?q=TEST", ""):
            with self.subTest(value=value):
                self.assertEqual(self.patch(value).status_code, 200, value)

    def test_other_links_are_refused_in_french(self):
        for value in ("http://maps.app.goo.gl/TEST", "https://exemple.test/maps", "https://www.google.com/search?q=TEST",
                      "https://maps.app.goo.gl.exemple.test/TEST", "https://user@maps.app.goo.gl/TEST", "javascript:alert(1)"):
            with self.subTest(value=value):
                response = self.patch(value)
                self.assertEqual(response.status_code, 400, value)
                self.assertIn("Google Maps", str(response.data))

    def test_only_admin_can_change_it_and_clients_see_it(self):
        self.patch("https://maps.app.goo.gl/TEST")
        self.client.force_authenticate(self.context["counter"] if "counter" in self.context else self.context["client"])
        self.assertIn(self.patch("https://maps.app.goo.gl/AUTRE").status_code, (403, 405))
        self.client.force_authenticate(None)
        locations = self.client.get("/api/v1/client/locations/").json()
        rows = locations["results"] if isinstance(locations, dict) else locations
        points = [pt for loc in rows for pt in loc.get("boarding_points", [])]
        self.assertIn("https://maps.app.goo.gl/TEST", [pt.get("map_url") for pt in points])
