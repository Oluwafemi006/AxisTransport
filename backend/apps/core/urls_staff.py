"""
Router dédié à la surface /api/v1/staff/.
Réservé aux employés d'AXIS (Contrôleurs, Guichet, Admin).
"""
from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import StaffSaleViewSet, StaffTicketViewSet

staff_router = DefaultRouter()
staff_router.register("tickets", StaffTicketViewSet, basename="staff-ticket")
staff_router.register("sales", StaffSaleViewSet, basename="staff-sale")

staff_urlpatterns = [
    path("", include(staff_router.urls)),
]
