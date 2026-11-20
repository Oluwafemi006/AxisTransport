"""Suivi public d'un colis : position du bus (dernière arrivée confirmée), confidentialité, codes inconnus (limite : test_parcel_tracking.py)."""
from django.core.cache import cache
from rest_framework.test import APITestCase

from apps.core.models import Location, Parcel, ParcelStatusHistory, RouteStop, TripStopArrival

from .factories import build_operational_context

TRACK = "/api/v1/client/parcels/track/"


class ParcelBusPositionTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        route = self.trip.route
        self.middle = Location.objects.create(name="Ville étape TEST")
        for position, location in enumerate([route.origin, self.middle, route.destination], start=1):
            RouteStop.objects.create(route=route, location=location, position=position)
        self.parcel = Parcel.objects.create(
            sender_name="Expéditeur TEST", sender_phone="0100000009", recipient_name="Destinataire TEST",
            recipient_phone="0100000008", origin=route.origin, destination=route.destination,
            description="Carton TEST confidentiel", trip=self.trip,
        )
        ParcelStatusHistory.objects.create(parcel=self.parcel, to_status=Parcel.Status.REGISTERED)

    def track(self, code=None):
        return self.client.get(TRACK, {"code": code or self.parcel.tracking_number})

    def set_status(self, status):
        Parcel.objects.filter(pk=self.parcel.pk).update(status=status)

    def test_loaded_without_arrival_shows_planned_departure(self):
        self.set_status(Parcel.Status.LOADED)
        bus = self.track().data["bus"]
        self.assertEqual(bus["stops"], ["Ville départ", "Ville étape TEST", "Ville arrivée"])
        self.assertIsNone(bus["last_stop"])
        self.assertIsNone(bus["last_confirmed_at"])
        self.assertTrue(bus["departure_at"].endswith("+01:00"), bus["departure_at"])

    def test_in_transit_shows_last_confirmed_city_in_benin_time(self):
        self.set_status(Parcel.Status.IN_TRANSIT)
        TripStopArrival.objects.create(trip=self.trip, location=self.middle, confirmed_by=self.context["controller"])
        bus = self.track().data["bus"]
        self.assertEqual(bus["last_stop"], "Ville étape TEST")
        self.assertTrue(bus["last_confirmed_at"].endswith("+01:00"), bus["last_confirmed_at"])

    def test_no_bus_before_loading_or_after_delivery_or_cancellation(self):
        for status in (Parcel.Status.REGISTERED, Parcel.Status.ARRIVED, Parcel.Status.READY_FOR_PICKUP,
                       Parcel.Status.PICKED_UP, Parcel.Status.CANCELLED):
            with self.subTest(status=status):
                self.set_status(status)
                response = self.track()
                self.assertEqual(response.status_code, 200, response.data)
                self.assertIsNone(response.data["bus"])

    def test_cancelled_parcel_answers_without_server_error(self):
        self.set_status(Parcel.Status.CANCELLED)
        response = self.track()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["current_step"], "Annulé")
        self.assertFalse(any(step["done"] for step in response.data["steps"]))

    def test_response_exposes_no_personal_or_vehicle_data(self):
        self.set_status(Parcel.Status.IN_TRANSIT)
        TripStopArrival.objects.create(trip=self.trip, location=self.middle, confirmed_by=self.context["controller"])
        data = self.track().data
        self.assertEqual(set(data), {"tracking_number", "origin", "destination", "current_step", "steps", "photos", "bus"})
        self.assertEqual(set(data["bus"]), {"stops", "departure_at", "last_stop", "last_confirmed_at"})
        text = str(data)
        for secret in ("Expéditeur TEST", "Destinataire TEST", "0100000009", "0100000008", "Carton TEST",
                       self.trip.vehicle.name, self.context["controller"].username):
            self.assertNotIn(secret, text)

    def test_unknown_codes_get_the_same_answer(self):
        first = self.client.get(TRACK, {"code": "AX-COL-0000000000"})
        second = self.client.get(TRACK, {"code": "AX-COL-FFFFFFFFFF"})
        third = self.client.get(TRACK, {"code": "n'importe quoi"})
        self.assertEqual({first.status_code, second.status_code, third.status_code}, {404})
        self.assertEqual(first.data, second.data)
        self.assertEqual(first.data, third.data)

    def test_most_advanced_stop_wins_over_the_latest_confirmation(self):
        self.set_status(Parcel.Status.IN_TRANSIT)
        controller = self.context["controller"]
        TripStopArrival.objects.create(trip=self.trip, location=self.trip.route.destination, confirmed_by=controller)
        TripStopArrival.objects.create(trip=self.trip, location=self.middle, confirmed_by=controller)
        self.assertEqual(self.track().data["bus"]["last_stop"], "Ville arrivée")
