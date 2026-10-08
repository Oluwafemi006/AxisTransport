"""
Tests de la surface API Client (/api/v1/client/).

Couvre :
- Accès autorisé (CLIENT authentifié)
- Accès refusé (COUNTER, CONTROLLER, ADMIN sur les endpoints client)
- Isolation de données (un client ne peut pas accéder aux données d'un autre)
- Réservation invité (guest_token)
- Méthodes HTTP non autorisées (405)
- Endpoints inexistants (404)
"""
from decimal import Decimal

from rest_framework.test import APITestCase

from apps.core.models import Booking, Parcel, Ticket, User
from apps.core.services import reserve_booking, reserve_ticket

from .factories import build_operational_context


CLIENT_BASE = "/api/v1/client"


class ClientSurfacePublicTests(APITestCase):
    """Endpoints publics : trajets, lieux, sièges, moyens de paiement."""

    def setUp(self):
        self.ctx = build_operational_context()

    def test_locations_public(self):
        r = self.client.get(f"{CLIENT_BASE}/locations/")
        self.assertEqual(r.status_code, 200)

    def test_trips_public(self):
        r = self.client.get(f"{CLIENT_BASE}/trips/")
        self.assertEqual(r.status_code, 200)

    def test_seats_public_requires_trip_param(self):
        """Sans ?trip=, la liste est vide. Pas d'exposition globale des sièges."""
        r = self.client.get(f"{CLIENT_BASE}/seats/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["count"], 0)

    def test_seats_public_with_trip(self):
        r = self.client.get(f"{CLIENT_BASE}/seats/?trip={self.ctx['trip'].pk}")
        self.assertEqual(r.status_code, 200)
        self.assertGreater(r.data["count"], 0)

    def test_payment_methods_public(self):
        r = self.client.get(f"{CLIENT_BASE}/payment-methods/")
        self.assertEqual(r.status_code, 200)

    def test_payment_methods_hide_internal_config(self):
        """configuration (clé interne) ne doit pas apparaître dans la réponse publique."""
        self.ctx["payment_method"].configuration = {"secret": "internal"}
        self.ctx["payment_method"].save()
        r = self.client.get(f"{CLIENT_BASE}/payment-methods/")
        self.assertEqual(r.status_code, 200)
        for item in r.data["results"]:
            self.assertNotIn("configuration", item)

    def test_vehicles_only_rental(self):
        """Seuls les véhicules de type RENTAL et ACTIVE sont exposés."""
        r = self.client.get(f"{CLIENT_BASE}/vehicles/")
        self.assertEqual(r.status_code, 200)
        # Le bus de test (BUS) ne doit pas apparaître ici.
        for v in r.data["results"]:
            self.assertEqual(v["category"], "RENTAL")

    def test_vehicles_hide_internal_fields(self):
        """registration_number et seat_labels ne doivent pas apparaître."""
        r = self.client.get(f"{CLIENT_BASE}/vehicles/")
        for v in r.data["results"]:
            self.assertNotIn("registration_number", v)
            self.assertNotIn("seat_labels", v)

    def test_trips_write_not_allowed(self):
        """Création de trajet impossible sur la surface client (ReadOnly)."""
        r = self.client.post(f"{CLIENT_BASE}/trips/", {})
        self.assertIn(r.status_code, [403, 405])

    def test_unknown_endpoint_returns_404(self):
        r = self.client.get(f"{CLIENT_BASE}/admin-stuff/")
        self.assertEqual(r.status_code, 404)


class ClientTicketTests(APITestCase):
    """Billets : ownership, isolation, refus du personnel interne."""

    def setUp(self):
        self.ctx = build_operational_context()
        self.client2 = User.objects.create_user(
            username="client2", password="secret2", role=User.Role.CLIENT
        )

    def test_client_can_list_own_tickets(self):
        reserve_ticket(
            trip=self.ctx["trip"],
            seat=self.ctx["trip"].seats.first(),
            customer=self.ctx["client"],
            passenger_name="Moi",
        )
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/tickets/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["count"], 1)

    def test_client_cannot_see_other_client_ticket_in_list(self):
        reserve_ticket(
            trip=self.ctx["trip"],
            seat=self.ctx["trip"].seats.first(),
            customer=self.client2,
            passenger_name="Autre",
        )
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/tickets/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["count"], 0)

    def test_client_cannot_access_other_client_ticket_by_id(self):
        seat = self.ctx["trip"].seats.first()
        other_ticket = reserve_ticket(
            trip=self.ctx["trip"],
            seat=seat,
            customer=self.client2,
            passenger_name="Autre",
        )
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/tickets/{other_ticket.pk}/")
        self.assertEqual(r.status_code, 404)

    def test_counter_cannot_list_tickets_on_client_surface(self):
        counter = User.objects.create_user(
            username="counter", password="secret", role=User.Role.COUNTER
        )
        self.client.force_authenticate(counter)
        r = self.client.get(f"{CLIENT_BASE}/tickets/")
        self.assertEqual(r.status_code, 403)

    def test_controller_cannot_create_ticket_on_client_surface(self):
        self.client.force_authenticate(self.ctx["controller"])
        r = self.client.post(f"{CLIENT_BASE}/tickets/", {
            "trip": self.ctx["trip"].pk,
            "seat": self.ctx["trip"].seats.first().pk,
            "passenger_name": "Test",
        })
        self.assertEqual(r.status_code, 403)

    def test_admin_cannot_use_client_ticket_surface(self):
        self.client.force_authenticate(self.ctx["admin"])
        r = self.client.get(f"{CLIENT_BASE}/tickets/")
        self.assertEqual(r.status_code, 403)

    def test_client_can_create_ticket(self):
        self.client.force_authenticate(self.ctx["client"])
        seats = self.ctx["trip"].seats.filter(status="AVAILABLE")
        r = self.client.post(f"{CLIENT_BASE}/tickets/", {
            "trip": self.ctx["trip"].pk,
            "seat": seats.first().pk,
            "passenger_name": "Voyageur Test",
        })
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data["channel"], Ticket.Channel.ONLINE)

    def test_ticket_channel_forced_online(self):
        """Même si le payload contient channel=COUNTER, il doit être ignoré."""
        self.client.force_authenticate(self.ctx["client"])
        seats = self.ctx["trip"].seats.filter(status="AVAILABLE")
        r = self.client.post(f"{CLIENT_BASE}/tickets/", {
            "trip": self.ctx["trip"].pk,
            "seat": seats.first().pk,
            "passenger_name": "Voyageur",
            "channel": Ticket.Channel.COUNTER,  # Tentative de forge
        })
        self.assertIn(r.status_code, [201, 400])
        if r.status_code == 201:
            self.assertEqual(r.data["channel"], Ticket.Channel.ONLINE)

    def test_unauthenticated_cannot_list_tickets(self):
        r = self.client.get(f"{CLIENT_BASE}/tickets/")
        # DRF retourne 401 (Unauthorized) quand aucun token n'est fourni,
        # et 403 (Forbidden) quand un token valide mais non autorisé est fourni.
        # Les deux réponses indiquent un accès refusé.
        self.assertIn(r.status_code, [401, 403])

    def test_http_delete_not_allowed_on_ticket(self):
        ticket = reserve_ticket(
            trip=self.ctx["trip"],
            seat=self.ctx["trip"].seats.first(),
            customer=self.ctx["client"],
            passenger_name="Moi",
        )
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.delete(f"{CLIENT_BASE}/tickets/{ticket.pk}/")
        self.assertEqual(r.status_code, 405)


class ClientBookingGuestTests(APITestCase):
    """Réservations invité : création, accès par guest_token, isolation."""

    def setUp(self):
        self.ctx = build_operational_context()
        self.seats = list(self.ctx["trip"].seats.all())

    def _make_booking_payload(self):
        return {
            "trip": self.ctx["trip"].pk,
            "contact_phone": "0600000000",
            "passengers": [
                {
                    "full_name": "Invité Test",
                    "phone": "0600000001",
                    "passenger_type": "ADULT",
                    "seat": self.seats[0].pk,
                }
            ],
        }

    def test_guest_can_create_booking(self):
        r = self.client.post(f"{CLIENT_BASE}/bookings/", self._make_booking_payload(), format="json")
        self.assertEqual(r.status_code, 201)
        self.assertIn("guest_access_token", r.data)

    def test_guest_can_retrieve_booking_with_token(self):
        r = self.client.post(f"{CLIENT_BASE}/bookings/", self._make_booking_payload(), format="json")
        self.assertEqual(r.status_code, 201)
        booking_id = r.data["id"]
        token = r.data["guest_access_token"]

        r2 = self.client.get(
            f"{CLIENT_BASE}/bookings/{booking_id}/",
            HTTP_X_BOOKING_TOKEN=token,
        )
        self.assertEqual(r2.status_code, 200)

    def test_guest_cannot_retrieve_booking_with_wrong_token(self):
        r = self.client.post(f"{CLIENT_BASE}/bookings/", self._make_booking_payload(), format="json")
        booking_id = r.data["id"]

        r2 = self.client.get(
            f"{CLIENT_BASE}/bookings/{booking_id}/",
            HTTP_X_BOOKING_TOKEN="mauvais-token",
        )
        self.assertEqual(r2.status_code, 403)

    def test_guest_cannot_retrieve_booking_without_token(self):
        r = self.client.post(f"{CLIENT_BASE}/bookings/", self._make_booking_payload(), format="json")
        booking_id = r.data["id"]

        r2 = self.client.get(f"{CLIENT_BASE}/bookings/{booking_id}/")
        self.assertEqual(r2.status_code, 403)

    def test_client_cannot_access_other_client_booking_by_id(self):
        client2 = User.objects.create_user(
            username="client2", password="secret", role=User.Role.CLIENT
        )
        r = self.client.post(f"{CLIENT_BASE}/bookings/", self._make_booking_payload(), format="json")
        booking_id = r.data["id"]

        self.client.force_authenticate(client2)
        r2 = self.client.get(f"{CLIENT_BASE}/bookings/{booking_id}/")
        self.assertEqual(r2.status_code, 403)

    def test_staff_cannot_create_booking_on_client_surface(self):
        counter = User.objects.create_user(
            username="counter", password="secret", role=User.Role.COUNTER
        )
        self.client.force_authenticate(counter)
        r = self.client.post(
            f"{CLIENT_BASE}/bookings/",
            self._make_booking_payload(),
            format="json",
        )
        self.assertEqual(r.status_code, 403)

    def test_booking_list_not_exposed_on_client_surface(self):
        """GET /bookings/ (liste globale) ne doit pas exister sur la surface client."""
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/bookings/")
        self.assertIn(r.status_code, [404, 405])


class ClientParcelTests(APITestCase):
    """Colis : ownership, isolation, refus du personnel interne."""

    def setUp(self):
        self.ctx = build_operational_context()
        self.client2 = User.objects.create_user(
            username="client2", password="secret2", role=User.Role.CLIENT
        )

    def _create_parcel_for(self, user):
        return Parcel.objects.create(
            customer=user,
            sender_name="Exp",
            sender_phone="0000",
            recipient_name="Dest",
            recipient_phone="1111",
            origin=self.ctx["origin"],
            destination=self.ctx["destination"],
            description="Colis",
        )

    def test_client_can_list_own_parcels(self):
        self._create_parcel_for(self.ctx["client"])
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/parcels/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["count"], 1)

    def test_client_cannot_see_other_client_parcel(self):
        self._create_parcel_for(self.client2)
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/parcels/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["count"], 0)

    def test_client_cannot_access_other_client_parcel_by_id(self):
        other_parcel = self._create_parcel_for(self.client2)
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/parcels/{other_parcel.pk}/")
        self.assertEqual(r.status_code, 404)

    def test_counter_cannot_access_client_parcel_surface(self):
        counter = User.objects.create_user(
            username="counter", password="secret", role=User.Role.COUNTER
        )
        self.client.force_authenticate(counter)
        r = self.client.get(f"{CLIENT_BASE}/parcels/")
        self.assertEqual(r.status_code, 403)

    def test_parcel_transition_not_exposed_on_client_surface(self):
        """L'action /transition/ (réservée au guichet) ne doit pas exister ici."""
        parcel = self._create_parcel_for(self.ctx["client"])
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.post(f"{CLIENT_BASE}/parcels/{parcel.pk}/transition/", {"status": "DEPOSITED"})
        self.assertEqual(r.status_code, 404)


class ClientRentalTests(APITestCase):
    """Locations : ownership, refus du personnel interne."""

    def setUp(self):
        self.ctx = build_operational_context()

    def test_counter_cannot_access_rental_on_client_surface(self):
        counter = User.objects.create_user(
            username="counter2", password="secret", role=User.Role.COUNTER
        )
        self.client.force_authenticate(counter)
        r = self.client.get(f"{CLIENT_BASE}/rentals/")
        self.assertEqual(r.status_code, 403)

    def test_client_can_list_own_rentals(self):
        self.client.force_authenticate(self.ctx["client"])
        r = self.client.get(f"{CLIENT_BASE}/rentals/")
        self.assertEqual(r.status_code, 200)
