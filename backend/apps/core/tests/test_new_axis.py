from datetime import time
from io import StringIO
from unittest.mock import patch

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from apps.core.axis import AXIS_STOPS
from apps.core.models import (
    BoardingPoint,
    LineStop,
    Location,
    Route,
    RouteStop,
    SegmentFare,
    SegmentFareChange,
    WeeklySchedule,
)

OLD_STOPS = ["Parakou", "Savè", "Kétou", "Porto-Novo", "Cotonou"]
OLD_FARES = {
    ("Parakou", "Cotonou"): 7500, ("Parakou", "Porto-Novo"): 7500, ("Parakou", "Kétou"): 6500,
    ("Parakou", "Savè"): 4500, ("Savè", "Cotonou"): 6500, ("Savè", "Porto-Novo"): 6500,
    ("Savè", "Kétou"): 2500, ("Kétou", "Porto-Novo"): 4000, ("Kétou", "Cotonou"): 4000,
    ("Porto-Novo", "Cotonou"): 1500,
}


def run(name, *args):
    out = StringIO()
    call_command(name, *args, stdout=out)
    return out.getvalue()


def build_old_axis():
    """Base telle que la produit main avant le changement d'axe."""
    places = {name: Location.objects.create(name=name, active=name in {"Parakou", "Cotonou"}) for name in OLD_STOPS}
    stops = {name: LineStop.objects.create(location=places[name], position=i) for i, name in enumerate(OLD_STOPS, 1)}
    for (a, b), amount in OLD_FARES.items():
        SegmentFare.objects.create(start=stops[a], end=stops[b], amount=amount)
    forward = Route.objects.create(origin=places["Parakou"], destination=places["Cotonou"])
    backward = Route.objects.create(origin=places["Cotonou"], destination=places["Parakou"])
    for route, names in ((forward, OLD_STOPS), (backward, list(reversed(OLD_STOPS)))):
        for i, name in enumerate(names, 1):
            RouteStop.objects.create(route=route, location=places[name], position=i)
    BoardingPoint.objects.create(location=places["Parakou"], name="Parc ALBARIKA", order=1)
    # Horaire modifié dans l'admin : ne doit jamais être réécrit au démarrage.
    WeeklySchedule.objects.create(day_of_week=WeeklySchedule.DayOfWeek.MONDAY, departure_time=time(9, 30), route=forward)
    return forward, backward


def fare(a, b):
    first, second = sorted(
        (LineStop.objects.get(location__name=a), LineStop.objects.get(location__name=b)), key=lambda s: s.position
    )
    return SegmentFare.objects.get(start=first, end=second).amount


def route_names(route):
    return list(route.stops.order_by("position").values_list("location__name", flat=True))


class OldAxisStartupTests(TestCase):
    def setUp(self):
        self.forward, self.backward = build_old_axis()

    def test_startup_on_old_axis_does_not_fail_nor_rewrite_anything(self):
        out = run("bootstrap_axis")
        self.assertIn("apply_axis", out)  # avertissement, pas d'échec du démarrage
        self.assertEqual(route_names(self.forward), OLD_STOPS)
        self.assertEqual(fare("Parakou", "Savè"), 4500)
        monday = WeeklySchedule.objects.get(day_of_week=WeeklySchedule.DayOfWeek.MONDAY)
        self.assertEqual(monday.departure_time, time(9, 30))

    def test_a_failure_during_apply_axis_changes_nothing(self):
        """Une panne pendant le second parcours annule tout : villes, ligne et premier parcours."""
        from apps.core import axis

        real = axis.set_route_stops
        calls = []

        def fail_on_second_route(route, names):
            calls.append(route)
            if len(calls) == 2:
                raise RuntimeError("TEST panne")
            return real(route, names)

        with patch("apps.core.management.commands.apply_axis.set_route_stops", side_effect=fail_on_second_route):
            with self.assertRaises(RuntimeError):
                run("apply_axis")
        self.assertEqual(len(calls), 2)
        self.assertEqual(route_names(self.forward), OLD_STOPS)
        self.assertEqual(route_names(self.backward), list(reversed(OLD_STOPS)))
        self.assertEqual(
            list(LineStop.objects.order_by("position").values_list("location__name", flat=True)), OLD_STOPS
        )
        self.assertFalse(Location.objects.filter(name__in=["Glazoué", "Dassa", "Bohicon"]).exists())
        self.assertFalse(Location.objects.get(name="Savè").active)

    def test_fares_command_refuses_before_the_axis(self):
        with self.assertRaises(CommandError):
            run("apply_axis_fares")


class TransitionTests(TestCase):
    def setUp(self):
        self.forward, self.backward = build_old_axis()
        self.fares_before = SegmentFare.objects.count()
        run("apply_axis")

    def test_line_and_both_routes_follow_the_new_order(self):
        self.assertEqual(
            list(LineStop.objects.filter(position__lte=6).order_by("position").values_list("location__name", flat=True)),
            AXIS_STOPS,
        )
        self.assertEqual(route_names(self.forward), AXIS_STOPS)
        self.assertEqual(route_names(self.backward), list(reversed(AXIS_STOPS)))

    def test_retired_cities_are_inactive_and_kept(self):
        for name in ("Kétou", "Porto-Novo"):
            place = Location.objects.get(name=name)
            self.assertFalse(place.active)
            self.assertFalse(RouteStop.objects.filter(location=place).exists())
            self.assertGreater(LineStop.objects.get(location=place).position, 100)
        self.assertEqual(SegmentFare.objects.count(), self.fares_before)
        self.assertTrue(Location.objects.filter(name__in=AXIS_STOPS, active=False).count() == 0)

    def test_fares_command_updates_two_creates_five_and_touches_nothing_else(self):
        out = run("apply_axis_fares")
        self.assertIn("Parakou ↔ Savè : 4500 → 3500 FCFA (modifié).", out)
        self.assertIn("Savè ↔ Cotonou : 6500 → 6000 FCFA (modifié).", out)
        self.assertIn("Parakou ↔ Cotonou : 7500 FCFA (inchangé).", out)
        self.assertEqual(out.count("(créé)"), 5)
        for (a, b), amount in {("Parakou", "Bohicon"): 6000, ("Parakou", "Glazoué"): 5000, ("Parakou", "Dassa"): 5000,
                               ("Savè", "Bohicon"): 3000, ("Bohicon", "Cotonou"): 3000, ("Parakou", "Savè"): 3500,
                               ("Savè", "Cotonou"): 6000}.items():
            self.assertEqual(fare(a, b), amount)
        # Ancien tarif conservé ; Kétou étant hors ligne, l'ordre de la paire s'inverse et il n'est plus utilisable.
        self.assertTrue(SegmentFare.objects.filter(start__location__name="Kétou", end__location__name="Cotonou", amount=4000).exists())
        self.assertEqual(SegmentFare.objects.count(), self.fares_before + 5)
        self.assertEqual(SegmentFareChange.objects.count(), 7)
        for pair in (("Savè", "Glazoué"), ("Glazoué", "Dassa"), ("Dassa", "Bohicon"), ("Glazoué", "Cotonou")):
            with self.assertRaises(SegmentFare.DoesNotExist):
                fare(*pair)
        second = run("apply_axis_fares")
        self.assertEqual(second.count("(inchangé)"), 8)

    def test_transition_is_idempotent_and_startup_then_works(self):
        run("apply_axis")
        run("apply_axis_fares")
        out = run("bootstrap_axis")
        self.assertNotIn("Grille des tronçons non chargée", out)
        self.assertEqual(route_names(self.forward), AXIS_STOPS)
        self.assertEqual(SegmentFare.objects.count(), self.fares_before + 5)
        monday = WeeklySchedule.objects.get(day_of_week=WeeklySchedule.DayOfWeek.MONDAY)
        self.assertEqual(monday.departure_time, time(9, 30))
        points = dict(BoardingPoint.objects.values_list("name", "location__name"))
        self.assertEqual(points, {"Parc ALBARIKA": "Parakou", "Bohicon": "Bohicon", "Calavi": "Cotonou", "Agontikon": "Cotonou"})


class BoardingPointsTests(TestCase):
    def test_a_city_changed_in_the_admin_is_not_completed(self):
        cotonou = Location.objects.create(name="Cotonou")
        BoardingPoint.objects.create(location=cotonou, name="TEST Gare renommée", active=False)
        run("load_boarding_points")
        self.assertEqual(list(cotonou.boarding_points.values_list("name", flat=True)), ["TEST Gare renommée"])

    def test_no_city_is_created(self):
        run("load_boarding_points")
        self.assertFalse(Location.objects.exists())


class FreshDatabaseTests(TestCase):
    def test_new_database_gets_the_new_axis_directly(self):
        run("bootstrap_axis")
        forward = Route.objects.get(origin__name="Parakou", destination__name="Cotonou")
        self.assertEqual(route_names(forward), AXIS_STOPS)
        self.assertEqual(SegmentFare.objects.count(), 8)
        self.assertEqual(fare("Parakou", "Glazoué"), 5000)
        self.assertFalse(Location.objects.filter(name__in=["Kétou", "Porto-Novo"]).exists())
