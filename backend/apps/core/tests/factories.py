from datetime import datetime, time, timedelta
from decimal import Decimal

from django.utils import timezone

from apps.core.models import FareRule, LineStop, Location, PaymentMethod, Route, SegmentFare, SystemSetting, Trip, User, Vehicle
from apps.core.services import generate_trip_seats


def build_operational_context(*, trip_date=None):
    origin = Location.objects.create(name="Ville départ")
    destination = Location.objects.create(name="Ville arrivée")
    route = Route.objects.create(origin=origin, destination=destination)
    vehicle = Vehicle.objects.create(category=Vehicle.Category.BUS, name="Bus test", capacity=4)
    trip_date = trip_date or timezone.localdate()
    departure = timezone.make_aware(datetime.combine(trip_date, time(hour=10)))
    arrival = departure + timedelta(hours=4)
    trip = Trip.objects.create(route=route, vehicle=vehicle, departure_at=departure, arrival_at=arrival)
    generate_trip_seats(trip)
    # Prix du billet : grille par tronçon (trajet complet). La règle du parcours, gardée, ne fixe plus le prix.
    segment_fare = SegmentFare.objects.create(
        start=LineStop.objects.create(location=origin, position=1),
        end=LineStop.objects.create(location=destination, position=2),
        amount=1000,
    )
    FareRule.objects.create(
        route=route,
        name="Tarif test configuré",
        rule_type=FareRule.RuleType.STANDARD,
        amount=Decimal("1000.00"),
    )
    SystemSetting.objects.create(key="ticket_hold_minutes", value=10)
    payment_method = PaymentMethod.objects.create(code="test", label="Paiement test", active=True)
    client = User.objects.create_user(username="client", password="secret", role=User.Role.CLIENT)
    controller = User.objects.create_user(username="controller", password="secret", role=User.Role.CONTROLLER)
    admin = User.objects.create_user(username="admin", password="secret", role=User.Role.ADMIN)
    return {
        "origin": origin,
        "destination": destination,
        "route": route,
        "vehicle": vehicle,
        "trip": trip,
        "payment_method": payment_method,
        "segment_fare": segment_fare,
        "client": client,
        "controller": controller,
        "admin": admin,
    }

