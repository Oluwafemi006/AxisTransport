from datetime import datetime, time, timedelta
from decimal import Decimal
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    LineStop,
    Location,
    PaymentMethod,
    Route,
    RouteStop,
    SegmentFare,
    SegmentFareChange,
    SystemSetting,
    Trip,
    User,
    Vehicle,
)
from apps.core.services import generate_trip_seats, resolve_segment_fare


class WaypointDirectionSearchTests(APITestCase):
    def setUp(self):
        # Création des 5 villes de la ligne
        self.parakou = Location.objects.create(name="Parakou", address="Okédama", active=True)
        self.save = Location.objects.create(name="Savè", active=True)
        self.ketou = Location.objects.create(name="Kétou", active=True)
        self.porto = Location.objects.create(name="Porto-Novo", active=True)
        self.cotonou = Location.objects.create(name="Cotonou", active=True)

        # LineStop (ordre de la ligne Parakou ↔ Cotonou)
        self.ls_parakou = LineStop.objects.create(location=self.parakou, position=1)
        self.ls_save = LineStop.objects.create(location=self.save, position=2)
        self.ls_ketou = LineStop.objects.create(location=self.ketou, position=3)
        self.ls_porto = LineStop.objects.create(location=self.porto, position=4)
        self.ls_cotonou = LineStop.objects.create(location=self.cotonou, position=5)

        # Grille tarifaire pour les tronçons
        def _add_fare(start_ls, end_ls, amount):
            fare = SegmentFare.objects.create(start=start_ls, end=end_ls, amount=amount)
            SegmentFareChange.objects.create(fare=fare, old_amount=None, new_amount=amount)
            return fare

        _add_fare(self.ls_parakou, self.ls_cotonou, 7500)
        _add_fare(self.ls_save, self.ls_cotonou, 6500)
        _add_fare(self.ls_save, self.ls_porto, 6500)
        _add_fare(self.ls_save, self.ls_ketou, 2500)
        _add_fare(self.ls_parakou, self.ls_save, 4500)

        # Véhicule bus Yutong
        self.vehicle = Vehicle.objects.create(
            category=Vehicle.Category.BUS,
            name="Yutong 50 places",
            capacity=50,
            state=Vehicle.State.ACTIVE,
        )

        # Itinéraire Descendant (Parakou → Cotonou)
        self.route_down = Route.objects.create(origin=self.parakou, destination=self.cotonou, active=True)
        for pos, loc in enumerate([self.parakou, self.save, self.ketou, self.porto, self.cotonou], start=1):
            RouteStop.objects.create(route=self.route_down, location=loc, position=pos)

        # Itinéraire Montant (Cotonou → Parakou)
        self.route_up = Route.objects.create(origin=self.cotonou, destination=self.parakou, active=True)
        for pos, loc in enumerate([self.cotonou, self.porto, self.ketou, self.save, self.parakou], start=1):
            RouteStop.objects.create(route=self.route_up, location=loc, position=pos)

        # Trajet Descendant (demain à 08h00)
        tomorrow = timezone.localdate() + timedelta(days=1)
        dep_down = timezone.make_aware(datetime.combine(tomorrow, time(8, 0)))
        arr_down = timezone.make_aware(datetime.combine(tomorrow, time(16, 0)))
        self.trip_down = Trip.objects.create(
            route=self.route_down,
            vehicle=self.vehicle,
            departure_at=dep_down,
            arrival_at=arr_down,
            status=Trip.Status.SCHEDULED,
        )
        generate_trip_seats(self.trip_down)

        # Trajet Montant (après-demain à 08h00)
        after_tomorrow = timezone.localdate() + timedelta(days=2)
        dep_up = timezone.make_aware(datetime.combine(after_tomorrow, time(8, 0)))
        arr_up = timezone.make_aware(datetime.combine(after_tomorrow, time(16, 0)))
        self.trip_up = Trip.objects.create(
            route=self.route_up,
            vehicle=self.vehicle,
            departure_at=dep_up,
            arrival_at=arr_up,
            status=Trip.Status.SCHEDULED,
        )
        generate_trip_seats(self.trip_up)

        SystemSetting.objects.create(key="ticket_hold_minutes", value=10)
        PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)

    def test_search_valid_save_to_cotonou_on_descending_bus(self):
        """
        Recherche valide Savè → Cotonou :
        Le bus Parakou → Cotonou (descendant) dessert Savè (index 2) puis Cotonou (index 5).
        Index départ (2) < Index arrivée (5) : le trajet doit être retourné.
        Le prix calculé doit être celui du tronçon Savè ↔ Cotonou (6 500 FCFA).
        """
        # Par IDs
        response = self.client.get(
            f"/api/v1/client/trips/?origin={self.save.id}&destination={self.cotonou.id}"
        )
        self.assertEqual(response.status_code, 200)
        results = response.json()
        trips = results.get("results", results) if isinstance(results, dict) else results
        trip_ids = [t["id"] for t in trips]
        self.assertIn(self.trip_down.id, trip_ids)
        self.assertNotIn(self.trip_up.id, trip_ids)

        # Vérification du tarif segmentaire retourné dans current_fare
        trip_data = next(t for t in trips if t["id"] == self.trip_down.id)
        self.assertIsNotNone(trip_data["current_fare"])
        self.assertEqual(trip_data["current_fare"]["amount"], 6500)

        # Par noms de ville
        response_names = self.client.get("/api/v1/client/trips/?origin=Savè&destination=Cotonou")
        self.assertEqual(response_names.status_code, 200)
        res_names = response_names.json()
        trips_names = res_names.get("results", res_names) if isinstance(res_names, dict) else res_names
        self.assertEqual([t["id"] for t in trips_names], [self.trip_down.id])

    def test_search_invalid_save_to_cotonou_on_ascending_bus(self):
        """
        Recherche invalide Savè → Cotonou sur un bus montant (Cotonou → Parakou) :
        Sur ce bus, Cotonou est à l'index 1 et Savè à l'index 4.
        Dans le sens de circulation, Savè (4) vient APRÈS Cotonou (1).
        Le bus ne doit absolument PAS être proposé à un voyageur voulant aller de Savè à Cotonou.
        """
        # Date ciblée sur le jour du bus montant
        date_str = timezone.localdate(self.trip_up.departure_at).isoformat()
        response = self.client.get(
            f"/api/v1/client/trips/?origin={self.save.id}&destination={self.cotonou.id}&date={date_str}"
        )
        self.assertEqual(response.status_code, 200)
        results = response.json()
        trips = results.get("results", results) if isinstance(results, dict) else results
        self.assertEqual(len(trips), 0, "Le bus montant ne doit pas apparaître pour Savè → Cotonou.")

    def test_search_valid_cotonou_to_save_on_ascending_bus(self):
        """
        Recherche valide Cotonou → Savè sur le bus montant :
        Cotonou (index 1) précède Savè (index 4) : le bus montant doit être proposé.
        """
        date_str = timezone.localdate(self.trip_up.departure_at).isoformat()
        response = self.client.get(
            f"/api/v1/client/trips/?origin={self.cotonou.id}&destination={self.save.id}&date={date_str}"
        )
        self.assertEqual(response.status_code, 200)
        results = response.json()
        trips = results.get("results", results) if isinstance(results, dict) else results
        self.assertEqual(len(trips), 1)
        self.assertEqual(trips[0]["id"], self.trip_up.id)
        self.assertEqual(trips[0]["current_fare"]["amount"], 6500)

    def test_search_same_origin_and_destination_returns_empty(self):
        """Une recherche avec départ == arrivée ne renvoie aucun trajet."""
        response = self.client.get(f"/api/v1/client/trips/?origin={self.save.id}&destination={self.save.id}")
        self.assertEqual(response.status_code, 200)
        results = response.json()
        trips = results.get("results", results) if isinstance(results, dict) else results
        self.assertEqual(len(trips), 0)

    def test_search_city_not_on_route_returns_empty(self):
        """Une ville inconnue ou non desservie ne renvoie aucun trajet."""
        response = self.client.get("/api/v1/client/trips/?origin=Inconnue&destination=Cotonou")
        self.assertEqual(response.status_code, 200)
        results = response.json()
        trips = results.get("results", results) if isinstance(results, dict) else results
        self.assertEqual(len(trips), 0)

    def test_search_action_endpoint(self):
        """L'action /client/trips/search/ applique exactement le même filtrage directionnel."""
        response = self.client.get(
            f"/api/v1/client/trips/search/?origin={self.save.id}&destination={self.cotonou.id}"
        )
        self.assertEqual(response.status_code, 200)
        results = response.json()
        trips = results.get("results", results) if isinstance(results, dict) else results
        self.assertEqual([t["id"] for t in trips], [self.trip_down.id])

    def test_client_locations_returns_all_active_stops_in_order(self):
        """Vérifie que /client/locations/ expose bien toutes les villes intermédiaires dans l'ordre de passage."""
        response = self.client.get("/api/v1/client/locations/")
        self.assertEqual(response.status_code, 200)
        results = response.json()
        items = results.get("results", results) if isinstance(results, dict) else results
        names = [item["name"] for item in items]
        self.assertEqual(names, ["Parakou", "Savè", "Kétou", "Porto-Novo", "Cotonou"])

    def test_payment_quote_with_waypoint_direction(self):
        """Le devis payment-quotes prend en compte le tronçon demandé."""
        response = self.client.get(
            f"/api/v1/client/trips/{self.trip_down.id}/payment-quotes/?passengers=2&origin={self.save.id}&destination={self.cotonou.id}"
        )
        self.assertEqual(response.status_code, 200)
        quotes = response.json()
        self.assertTrue(len(quotes) >= 1)
        # 2 passagers × 6 500 = 13 000 FCFA
        self.assertEqual(Decimal(str(quotes[0]["amount"])), Decimal("13000"))

    def test_route_model_methods_and_line_stop_fallback(self):
        """Vérifie get_stops_sequence, has_waypoint_direction et le repli sur LineStop si RouteStop absent."""
        # Avec RouteStop
        self.assertTrue(self.route_down.has_waypoint_direction(self.save, self.cotonou))
        self.assertFalse(self.route_down.has_waypoint_direction(self.cotonou, self.save))
        self.assertTrue(self.route_up.has_waypoint_direction(self.cotonou, self.save))
        self.assertFalse(self.route_up.has_waypoint_direction(self.save, self.cotonou))

        # Suppression des RouteStop pour tester le repli sur LineStop
        self.route_down.stops.all().delete()
        self.route_up.stops.all().delete()
        self.assertTrue(self.route_down.has_waypoint_direction("Savè", "Cotonou"))
        self.assertFalse(self.route_down.has_waypoint_direction("Cotonou", "Savè"))
        self.assertTrue(self.route_up.has_waypoint_direction("Cotonou", "Savè"))
        self.assertFalse(self.route_up.has_waypoint_direction("Savè", "Cotonou"))
