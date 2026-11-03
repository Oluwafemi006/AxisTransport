"""Axe Parakou ↔ Cotonou : arrêts, tarifs et points d'embarquement validés par le boss (transmis par Eddy)."""
from django.db import transaction

from .models import LineStop, Location, Route, RouteStop

# Ordre de Parakou vers Cotonou ; le retour suit l'ordre inverse.
AXIS_STOPS = ["Parakou", "Savè", "Glazoué", "Dassa", "Bohicon", "Cotonou"]

# Anciennes villes de la ligne : désactivées, jamais supprimées (tarifs et historique conservés).
RETIRED_STOPS = ["Kétou", "Porto-Novo"]

# Prix en francs CFA, identiques dans les deux sens. Aucun autre tronçon n'a de tarif.
AXIS_FARES = {
    ("Parakou", "Cotonou"): 7500,
    ("Parakou", "Bohicon"): 6000,
    ("Parakou", "Glazoué"): 5000,
    ("Parakou", "Dassa"): 5000,
    ("Parakou", "Savè"): 3500,
    ("Savè", "Cotonou"): 6000,
    ("Savè", "Bohicon"): 3000,
    ("Bohicon", "Cotonou"): 3000,
}

# Points créés seulement pour une ville qui n'en a aucun.
AXIS_BOARDING_POINTS = {
    "Parakou": ["Parc ALBARIKA"],
    "Bohicon": ["Bohicon"],
    "Cotonou": ["Calavi", "Agontikon"],
}

# Les rangs des arrêts retirés sont repoussés au-delà de cette valeur, hors de la ligne.
RETIRED_POSITION_OFFSET = 100


def axis_routes():
    """Parcours Parakou → Cotonou et Cotonou → Parakou (créés s'ils manquent)."""
    parakou, _ = Location.objects.get_or_create(name="Parakou")
    cotonou, _ = Location.objects.get_or_create(name="Cotonou")
    forward, _ = Route.objects.get_or_create(origin=parakou, destination=cotonou)
    backward, _ = Route.objects.get_or_create(origin=cotonou, destination=parakou)
    return forward, backward


@transaction.atomic
def set_route_stops(route, names):
    """Arrêts du parcours dans l'ordre donné ; les autres arrêts du parcours sont retirés (pas les lieux)."""
    places = [Location.objects.get(name=name) for name in names]
    removed = list(route.stops.exclude(location__in=places).values_list("location__name", flat=True))
    route.stops.exclude(location__in=places).delete()
    # Rangs uniques par parcours : on les écarte d'abord pour pouvoir les réordonner.
    for stop in route.stops.all():
        stop.position += 1000
        stop.save(update_fields=["position"])
    for position, place in enumerate(places, start=1):
        stop = route.stops.filter(location=place).first()
        if stop is None:
            RouteStop.objects.create(route=route, location=place, position=position)
        else:
            stop.position = position
            stop.save(update_fields=["position"])
    return removed


@transaction.atomic
def set_line_stops(names):
    """Rangs de la ligne (tarifs) ; tout autre arrêt est repoussé au-delà de RETIRED_POSITION_OFFSET."""
    places = {name: Location.objects.get(name=name) for name in names}
    others = list(LineStop.objects.exclude(location__in=places.values()).order_by("position"))
    for stop in LineStop.objects.all():
        stop.position += 1000
        stop.save(update_fields=["position"])
    for index, stop in enumerate(others, start=1):
        stop.position = RETIRED_POSITION_OFFSET + index
        stop.save(update_fields=["position"])
    for position, name in enumerate(names, start=1):
        stop = LineStop.objects.filter(location=places[name]).first()
        if stop is None:
            LineStop.objects.create(location=places[name], position=position)
        else:
            stop.position = position
            stop.save(update_fields=["position"])
    return [stop.location.name for stop in others]
