from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    BookingViewSet,
    DashboardView,
    FareRuleViewSet,
    FeatureFlagViewSet,
    LocationViewSet,
    MeView,
    RegisterView,
    ParcelViewSet,
    PaymentIncidentViewSet,
    SegmentFareChangeViewSet,
    ManualTicketChangeViewSet,
    SegmentFareViewSet,
    PaymentMethodViewSet,
    RentalBookingViewSet,
    RouteViewSet,
    SeatViewSet,
    SystemSettingViewSet,
    TicketViewSet,
    TransactionViewSet,
    TripViewSet,
    UserViewSet,
    VehicleViewSet,
    health,
)


router = DefaultRouter()
router.register("locations", LocationViewSet)
router.register("routes", RouteViewSet)
router.register("vehicles", VehicleViewSet)
router.register("trips", TripViewSet)
router.register("seats", SeatViewSet)
router.register("fare-rules", FareRuleViewSet)
router.register("feature-flags", FeatureFlagViewSet)
router.register("settings", SystemSettingViewSet)
router.register("users", UserViewSet)
router.register("tickets", TicketViewSet)
router.register("bookings", BookingViewSet)
router.register("parcels", ParcelViewSet)
router.register("rentals", RentalBookingViewSet)
router.register("payment-methods", PaymentMethodViewSet)
router.register("payment-incidents", PaymentIncidentViewSet)
router.register("segment-fares", SegmentFareViewSet)
router.register("segment-fare-changes", SegmentFareChangeViewSet)
router.register("ticket-manual-changes", ManualTicketChangeViewSet, basename="ticket-manual-change")
router.register("transactions", TransactionViewSet)

urlpatterns = [
    path("health/", health),
    path("auth/me/", MeView.as_view()),
    path("auth/register/", RegisterView.as_view()),
    path("dashboard/", DashboardView.as_view()),
    path("", include(router.urls)),
]
