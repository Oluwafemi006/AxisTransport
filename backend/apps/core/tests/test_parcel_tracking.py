from django.core.cache import cache
from rest_framework.test import APITestCase

from apps.core.models import Parcel, ParcelStatusHistory, User
from apps.core.services import transition_parcel

from .factories import build_operational_context

TRACK = "/api/v1/client/parcels/track/"


class ParcelRulesTests(APITestCase):
    def setUp(self):
        cache.clear()  # compteur de la limite de requêtes
        self.context = build_operational_context()
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        self.payload = {
            "sender_name": "Expéditeur Test",
            "sender_phone": "90000001",
            "recipient_name": "Destinataire Test",
            "recipient_phone": "90000002",
            "origin": self.context["origin"].pk,
            "destination": self.context["destination"].pk,
            "description": "Carton",
        }

    def _parcel(self):
        parcel = Parcel.objects.create(
            sender_name="Expéditeur Test",
            sender_phone="90000001",
            recipient_name="Destinataire Test",
            recipient_phone="90000002",
            origin=self.context["origin"],
            destination=self.context["destination"],
            description="Carton confidentiel",
        )
        ParcelStatusHistory.objects.create(parcel=parcel, to_status=Parcel.Status.REGISTERED)
        return parcel

    def test_client_cannot_create_parcel_on_any_surface(self):
        self.client.force_authenticate(self.context["client"])
        client_surface = self.client.post("/api/v1/client/parcels/", self.payload, format="json")
        legacy = self.client.post("/api/v1/parcels/", self.payload, format="json")
        self.assertEqual((client_surface.status_code, legacy.status_code), (405, 403))
        self.assertEqual(Parcel.objects.count(), 0)

    def test_anonymous_cannot_create_parcel(self):
        self.assertEqual(self.client.post("/api/v1/parcels/", self.payload, format="json").status_code, 401)
        self.assertEqual(Parcel.objects.count(), 0)

    def test_agency_registers_parcel(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post("/api/v1/parcels/", self.payload, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data["tracking_number"].startswith("AX-COL-"))

    def test_tracking_by_code_shows_customer_steps_only(self):
        parcel = self._parcel()
        response = self.client.get(TRACK, {"code": parcel.tracking_number.lower()})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [step["label"] for step in response.data["steps"]],
            ["Enregistré", "Chargé", "En transit", "Arrivé", "Disponible au retrait", "Retiré"],
        )
        self.assertEqual(response.data["current_step"], "Enregistré")
        self.assertEqual([step["done"] for step in response.data["steps"]], [True] + [False] * 5)
        body = response.content.decode()
        for private in ("Expéditeur Test", "Destinataire Test", "90000001", "90000002", "confidentiel"):
            self.assertNotIn(private, body)

    def test_internal_steps_stay_under_registered_then_progress(self):
        parcel = self._parcel()
        parcel.trip = self.context["trip"]
        parcel.save(update_fields=["trip"])
        for target in (Parcel.Status.DEPOSITED, Parcel.Status.ACCEPTED, Parcel.Status.ASSIGNED):
            transition_parcel(parcel, target, actor=self.counter)
        self.assertEqual(self.client.get(TRACK, {"code": parcel.tracking_number}).data["current_step"], "Enregistré")
        for target in (Parcel.Status.LOADED, Parcel.Status.IN_TRANSIT):
            transition_parcel(parcel, target, actor=self.counter)
        data = self.client.get(TRACK, {"code": parcel.tracking_number}).data
        self.assertEqual(data["current_step"], "En transit")
        self.assertEqual([step["done"] for step in data["steps"]], [True, True, True, False, False, False])
        self.assertIsNotNone(data["steps"][2]["reached_at"])
        self.assertIsNone(data["steps"][3]["reached_at"])

    def test_unknown_or_missing_code(self):
        self.assertEqual(self.client.get(TRACK, {"code": "AX-COL-INCONNU"}).status_code, 404)
        self.assertEqual(self.client.get(TRACK).status_code, 400)

    def test_tracking_codes_are_random_not_sequential(self):
        first, second = self._parcel().tracking_number, self._parcel().tracking_number
        suffixes = [int(code.removeprefix("AX-COL-"), 16) for code in (first, second)]
        self.assertEqual(len(first), len("AX-COL-") + 10)
        self.assertNotEqual(abs(suffixes[0] - suffixes[1]), 1)

    def test_tracking_is_rate_limited_per_address(self):
        parcel = self._parcel()
        statuses = [self.client.get(TRACK, {"code": "AX-COL-ESSAI%04d" % index}).status_code for index in range(20)]
        self.assertEqual(set(statuses), {404})
        # 21e recherche de la même adresse dans la minute : refusée, même avec un code valide.
        blocked = self.client.get(TRACK, {"code": parcel.tracking_number})
        self.assertEqual(blocked.status_code, 429)
        self.assertNotIn("steps", blocked.json())
        # Une autre adresse n'est pas pénalisée.
        other = self.client.get(TRACK, {"code": parcel.tracking_number}, REMOTE_ADDR="203.0.113.9")
        self.assertEqual(other.status_code, 200)
