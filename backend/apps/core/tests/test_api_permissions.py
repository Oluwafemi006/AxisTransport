from rest_framework.test import APITestCase

from apps.core.models import FareRule, FeatureFlag, Parcel, User
from apps.core.services import reserve_ticket

from .factories import build_operational_context


class RolePermissionTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()

    def test_client_cannot_change_fare(self):
        self.client.force_authenticate(self.context["client"])
        fare = FareRule.objects.first()
        response = self.client.patch(f"/api/fare-rules/{fare.pk}/", {"amount": "1.00"})
        self.assertEqual(response.status_code, 403)

    def test_admin_can_change_fare(self):
        self.client.force_authenticate(self.context["admin"])
        fare = FareRule.objects.first()
        response = self.client.patch(f"/api/fare-rules/{fare.pk}/", {"amount": "2000.00"})
        self.assertEqual(response.status_code, 200)

    def test_controller_cannot_sell_ticket(self):
        self.client.force_authenticate(self.context["controller"])
        response = self.client.post(
            "/api/tickets/",
            {
                "trip": self.context["trip"].pk,
                "seat": self.context["trip"].seats.first().pk,
                "passenger_name": "Voyageur",
            },
        )
        # Refus par permission (rôle non autorisé), et non plus par une erreur de validation.
        self.assertEqual(response.status_code, 403)

    def test_public_registration_always_creates_client(self):
        self.client.force_authenticate(user=None)
        response = self.client.post(
            "/api/auth/register/",
            {
                "username": "new-client",
                "password": "A-strong-client-password-2026",
                "first_name": "Nouveau",
                "role": User.Role.ADMIN,
            },
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(User.objects.get(username="new-client").role, User.Role.CLIENT)

    def test_controller_cannot_transition_parcel(self):
        parcel = Parcel.objects.create(
            sender_name="Expéditeur",
            sender_phone="00000000",
            recipient_name="Destinataire",
            recipient_phone="11111111",
            origin=self.context["origin"],
            destination=self.context["destination"],
            description="Colis test",
        )
        self.client.force_authenticate(self.context["controller"])
        response = self.client.post(
            f"/api/parcels/{parcel.pk}/transition/",
            {"status": Parcel.Status.DEPOSITED},
        )
        self.assertEqual(response.status_code, 403)

    def test_client_cannot_access_team_or_internal_settings(self):
        self.client.force_authenticate(self.context["client"])
        for path in ("/api/users/", "/api/settings/", "/api/dashboard/", "/api/trips/?all=true"):
            with self.subTest(path=path):
                self.assertEqual(self.client.get(path).status_code, 403)

    def test_client_cannot_modify_ticket_directly(self):
        ticket = reserve_ticket(
            trip=self.context["trip"],
            seat=self.context["trip"].seats.first(),
            customer=self.context["client"],
            passenger_name="Client Test",
        )
        self.client.force_authenticate(self.context["client"])
        response = self.client.patch(f"/api/tickets/{ticket.pk}/", {"passenger_name": "Nom remplacé"})
        self.assertEqual(response.status_code, 403)

    def test_client_cannot_modify_parcel_after_creation(self):
        parcel = Parcel.objects.create(
            customer=self.context["client"],
            sender_name="Expéditeur",
            sender_phone="00000000",
            recipient_name="Destinataire",
            recipient_phone="11111111",
            origin=self.context["origin"],
            destination=self.context["destination"],
            description="Colis test",
        )
        self.client.force_authenticate(self.context["client"])
        response = self.client.patch(f"/api/parcels/{parcel.pk}/", {"recipient_name": "Nom remplacé"})
        self.assertEqual(response.status_code, 403)

    def test_controller_only_lists_tickets_for_selected_trip(self):
        reserve_ticket(
            trip=self.context["trip"],
            seat=self.context["trip"].seats.first(),
            customer=self.context["client"],
            passenger_name="Client Test",
        )
        self.client.force_authenticate(self.context["controller"])
        unscoped = self.client.get("/api/tickets/")
        scoped = self.client.get(f"/api/tickets/?trip={self.context['trip'].pk}")
        self.assertEqual(unscoped.status_code, 200)
        self.assertEqual(unscoped.data["count"], 0)
        self.assertEqual(scoped.status_code, 200)
        self.assertEqual(scoped.data["count"], 1)
        self.assertNotIn("customer", scoped.data["results"][0])
        self.assertNotIn("customer_detail", scoped.data["results"][0])

    def test_public_responses_hide_internal_configuration(self):
        FeatureFlag.objects.create(
            key=FeatureFlag.Key.MOBILE_MONEY,
            enabled=False,
            configuration={"secret": "internal"},
        )
        self.context["vehicle"].registration_number = "INTERNAL-001"
        self.context["vehicle"].seat_configuration = [
            {"label": str(index), "row": index, "column": 1} for index in range(1, 5)
        ]
        self.context["vehicle"].save()
        self.context["payment_method"].configuration = {"secret": "internal"}
        self.context["payment_method"].save()
        self.client.force_authenticate(user=None)

        vehicle = self.client.get("/api/vehicles/").data["results"][0]
        payment = self.client.get("/api/payment-methods/").data["results"][0]
        flag = self.client.get("/api/feature-flags/").data["results"][0]

        self.assertNotIn("registration_number", vehicle)
        self.assertNotIn("seat_configuration", vehicle)
        self.assertNotIn("configuration", payment)
        self.assertNotIn("configuration", flag)
