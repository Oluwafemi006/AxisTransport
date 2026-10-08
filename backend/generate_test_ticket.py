import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from apps.core.models import Ticket, User, Trip, Route, Location, Vehicle, Seat
from django.utils import timezone

# Create minimum data to get a ticket
user, _ = User.objects.get_or_create(username='client_test', role=User.Role.CLIENT)
loc1, _ = Location.objects.get_or_create(name='Cotonou')
loc2, _ = Location.objects.get_or_create(name='Parakou')
route, _ = Route.objects.get_or_create(origin=loc1, destination=loc2)
vehicle, _ = Vehicle.objects.get_or_create(name='TestBus', category=Vehicle.Category.BUS)
trip, _ = Trip.objects.get_or_create(route=route, vehicle=vehicle, departure_at=timezone.now())
seat, _ = Seat.objects.get_or_create(trip=trip, number='A1')

ticket, created = Ticket.objects.get_or_create(
    trip=trip, 
    seat=seat, 
    defaults={
        'customer': user, 
        'passenger_name': 'Jean Dupont', 
        'passenger_phone': '12345678', 
        'status': Ticket.Status.PAID,
        'amount': 1000
    }
)

if not ticket.qr_token:
    ticket._generate_qr_token()
    ticket.save()

print(f"Billet généré avec succès ! Billet ID: {ticket.id}")
print(f"QR_TOKEN={ticket.qr_token}")
