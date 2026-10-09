"""
Router dédié à la surface publique /api/v1/client/.

PÉRIMÈTRE : Application mobile client uniquement.
ISOLATION : Chaque ViewSet ci-dessous a des permissions renforcées
            pour garantir qu'aucun staff interne ne peut utiliser
            cette surface pour effectuer des opérations internes.

RÈGLE FONDAMENTALE : Cacher une route dans Flutter ne constitue PAS une sécurité.
                     La sécurité est appliquée ici, côté serveur.

SURFACES À VENIR (non implémentées ici) :
  /api/v1/staff/   → CONTROLLER, COUNTER
  /api/v1/admin/   → ADMIN, OPERATIONS_MANAGER, etc.
"""
import hmac

from django.core.exceptions import ImproperlyConfigured, ValidationError as DjangoValidationError
from django.shortcuts import get_object_or_404
from django.urls import include, path
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.routers import DefaultRouter

from .models import (
    Booking,
    Location,
    Parcel,
    ParcelStatusHistory,
    PaymentMethod,
    RentalBooking,
    Seat,
    Ticket,
    Transaction,
    Trip,
    User,
    Vehicle,
)
from .permissions import IsClientOnly
from .serializers import (
    BookingCreateSerializer,
    BookingSerializer,
    LocationSerializer,
    ParcelSerializer,
    PaymentMethodSerializer,
    PublicPaymentMethodSerializer,
    PublicVehicleSerializer,
    RentalBookingSerializer,
    SeatSerializer,
    TicketCreateSerializer,
    TicketSerializer,
    TransactionSerializer,
    TripSerializer,
)
from .payments import settle_booking_payment, settle_ticket_payment
from .services import (
    hash_guest_token,
    is_plausible_phone,
    release_expired_holds,
    reserve_booking,
    reserve_ticket,
    transition_parcel,
)
from .views import (
    FedaPayWebhookView,
    KKiaPayWebhookView,
    ParcelTrackingView,
    PublicContactView,
    PublicTicketDetailView,
    checkout_response,
    refund_due_response,
    service_validation_error,
)

# ─── Helpers ─────────────────────────────────────────────────────────────────

def _is_client_or_guest(user):
    """Renvoie True si l'utilisateur est un CLIENT authentifié, ou non authentifié (invité)."""
    if not user.is_authenticated:
        return True
    return user.role == User.Role.CLIENT


# ─── ViewSets Client ─────────────────────────────────────────────────────────

class ClientLocationViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Villes et arrêts actifs. Lecture publique. Pas d'écriture (Admin uniquement).
    """
    queryset = Location.objects.filter(active=True)
    serializer_class = LocationSerializer
    permission_classes = [AllowAny]


class ClientTripViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Trajets planifiés à venir. Lecture publique.
    Pas d'accès aux trajets internes (?all=true), ni de création/modification.
    Appel à release_expired_holds() pour libérer les sièges expirés avant tout retour.
    """
    serializer_class = TripSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        from django.utils import timezone
        from datetime import datetime
        release_expired_holds()
        queryset = Trip.objects.select_related(
            "route__origin", "route__destination", "vehicle"
        ).prefetch_related("seats").filter(
            status__in=[Trip.Status.SCHEDULED, Trip.Status.BOARDING],
            departure_at__gte=timezone.now(),
        )
        origin = self.request.query_params.get("origin")
        destination = self.request.query_params.get("destination")
        date_value = self.request.query_params.get("date")
        if origin:
            queryset = queryset.filter(route__origin_id=origin)
        if destination:
            queryset = queryset.filter(route__destination_id=destination)
        if date_value:
            try:
                selected_date = datetime.strptime(date_value, "%Y-%m-%d").date()
            except ValueError as exc:
                raise ValidationError({"date": "Format attendu : AAAA-MM-JJ."}) from exc
            queryset = queryset.filter(departure_at__date=selected_date)
        return queryset


class ClientSeatViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Sièges d'un trajet. Lecture publique, filtrée obligatoirement par ?trip=.
    Sans ?trip=, retourne une liste vide (pas d'exposition globale des sièges).
    """
    serializer_class = SeatSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        release_expired_holds()
        trip = self.request.query_params.get("trip")
        if not trip:
            return Seat.objects.none()
        return Seat.objects.select_related("trip").filter(trip_id=trip)


class ClientPaymentMethodViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Moyens de paiement actifs. Lecture publique. Champs internes masqués.
    """
    queryset = PaymentMethod.objects.filter(active=True)
    serializer_class = PublicPaymentMethodSerializer
    permission_classes = [AllowAny]


class ClientVehicleViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Véhicules de location uniquement. Lecture publique.
    Seuls les véhicules RENTAL actifs sont exposés.
    Les données de configuration interne (registration_number, seat_labels, etc.)
    ne sont pas incluses grâce au PublicVehicleSerializer.
    """
    queryset = Vehicle.objects.filter(
        category=Vehicle.Category.RENTAL,
        state=Vehicle.State.ACTIVE,
    )
    serializer_class = PublicVehicleSerializer
    permission_classes = [AllowAny]


class ClientTicketViewSet(viewsets.GenericViewSet):
    """
    Billets du client connecté.

    SÉCURITÉ :
    - Seul un CLIENT authentifié peut créer ou consulter ses billets.
    - Un COUNTER ou ADMIN obtient un 403 sur cette surface.
    - GET /tickets/{id}/ vérifie que le billet appartient au client (ownership).
    - Le canal est forcé à ONLINE. La vente guichet sera exposée sur /staff/ ultérieurement.
    """
    serializer_class = TicketSerializer
    permission_classes = [IsClientOnly]

    def get_queryset(self):
        release_expired_holds()
        return Ticket.objects.select_related(
            "customer", "seat", "trip__route__origin",
            "trip__route__destination", "trip__vehicle"
        ).prefetch_related(
            "status_history", "controls"
        ).filter(customer=self.request.user)

    def list(self, request):
        queryset = self.get_queryset()
        serializer = self.get_serializer(queryset, many=True)
        return Response({"count": queryset.count(), "results": serializer.data})

    def retrieve(self, request, pk=None):
        """
        Retourne un billet uniquement s'il appartient au client connecté.
        Un client ne peut PAS accéder au billet d'un autre client via son ID.
        """
        ticket = get_object_or_404(self.get_queryset(), pk=pk)
        return Response(self.get_serializer(ticket).data)

    def create(self, request):
        """
        Réservation unitaire pour le client connecté.
        Le rôle COUNTER ne peut pas utiliser cet endpoint.
        Le canal est forcé à ONLINE.
        """
        serializer = TicketCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            ticket = reserve_ticket(
                trip=data["trip"],
                seat=data["seat"],
                customer=request.user,
                passenger_name=data["passenger_name"],
                passenger_phone=data.get("passenger_phone", ""),
                channel=Ticket.Channel.ONLINE,  # Forcé : jamais COUNTER sur cette surface.
            )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc)
        return Response(
            TicketSerializer(ticket, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"])
    def checkout(self, request, pk=None):
        """Crée la transaction chez le prestataire : montant fixé par le serveur, lien de paiement renvoyé."""
        return checkout_response(get_object_or_404(self.get_queryset(), pk=pk), request)

    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        """
        Paiement d'un billet du client. Vérifie l'ownership avant paiement.
        Le rôle COUNTER ne peut pas utiliser cet endpoint.
        """
        ticket = get_object_or_404(self.get_queryset(), pk=pk)
        payment_method = PaymentMethod.objects.filter(
            pk=request.data.get("payment_method"), active=True
        ).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable ou inactif."})

        # La vérification du paiement (statut, montant, unicité) est faite par settle_ticket_payment.
        try:
            settlement = settle_ticket_payment(
                ticket,
                payment_method=payment_method,
                actor=request.user,
                external_reference=request.data.get("external_reference", ""),
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        if settlement.refund_due:
            return refund_due_response()
        return Response({
            "ticket": TicketSerializer(settlement.target).data,
            "transaction": TransactionSerializer(settlement.transactions[0]).data,
        })


class ClientBookingViewSet(viewsets.GenericViewSet):
    """
    Réservations de groupe (multi-passagers).

    SÉCURITÉ :
    - Création : AllowAny (support des réservations invité sans compte).
    - Retrieve & Pay : Propriétaire OU guest_token valide.
    - Un client ne peut accéder qu'à ses propres réservations.
    - La liste globale n'est PAS exposée sur cette surface (pas de GET /bookings/).
    """
    serializer_class = BookingSerializer

    BASE_QUERYSET = Booking.objects.select_related(
        "customer",
        "trip__route__origin",
        "trip__route__destination",
        "trip__vehicle",
    ).prefetch_related(
        "passengers",
        "tickets__customer",
        "tickets__seat",
        "tickets__trip__route__origin",
        "tickets__trip__route__destination",
        "tickets__trip__vehicle",
        "tickets__status_history",
        "tickets__controls",
    )

    def get_permissions(self):
        # Création ouverte (invité + client), retrieve/pay restreints à l'owner/guest.
        return [AllowAny()]

    def _guest_token(self):
        return self.request.headers.get("X-Booking-Token") or self.request.data.get("guest_token", "")

    def _assert_can_access(self, booking):
        """
        Vérifie l'accès à une réservation :
        - Client propriétaire authentifié, OU
        - Invité avec un guest_token valide.
        Toute autre situation → 403.
        """
        user = self.request.user
        if user.is_authenticated:
            if user.role != User.Role.CLIENT:
                raise PermissionDenied("Le personnel interne ne doit pas utiliser la surface client pour accéder aux réservations.")
            if booking.customer_id == user.id:
                return
            raise PermissionDenied("Vous ne pouvez accéder qu'à vos propres réservations.")
        # Invité : vérification du guest_token
        token = self._guest_token()
        if booking.guest_token_hash and token and hmac.compare_digest(
            booking.guest_token_hash,
            hash_guest_token(token),
        ):
            return
        raise PermissionDenied("Accès à la réservation refusé.")

    def _get_booking(self, pk):
        release_expired_holds()
        booking = get_object_or_404(self.BASE_QUERYSET, pk=pk)
        self._assert_can_access(booking)
        return booking

    def _serialized_booking(self, booking, **extra):
        payload = BookingSerializer(booking, context={"request": self.request}).data
        payload.update(extra)
        return payload

    def create(self, request):
        """
        Réservation de groupe (invité ou client).
        Supporte les réservations sans compte (guest_token retourné si invité).
        """
        if request.user.is_authenticated and request.user.role != User.Role.CLIENT:
            raise PermissionDenied("Le personnel interne ne peut pas créer une réservation via la surface client.")
        serializer = BookingCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        customer = request.user if request.user.is_authenticated else None
        # Sans compte, le téléphone est le seul moyen de joindre le voyageur : il est obligatoire.
        if customer is None and not is_plausible_phone(data.get("contact_phone", "")):
            raise ValidationError(
                {"contact_phone": "Un numéro de téléphone valide est obligatoire pour réserver sans compte."}
            )
        try:
            booking, guest_token = reserve_booking(
                trip=data["trip"],
                passengers=data["passengers"],
                customer=customer,
                contact_phone=data.get("contact_phone", ""),
                contact_email=data.get("contact_email", ""),
            )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc)
        booking = self.BASE_QUERYSET.get(pk=booking.pk)
        extra = {"guest_access_token": guest_token} if guest_token else {}
        return Response(self._serialized_booking(booking, **extra), status=status.HTTP_201_CREATED)

    def retrieve(self, request, pk=None):
        """Consulter une réservation. Vérifie l'ownership ou le guest_token."""
        booking = self._get_booking(pk)
        return Response(self._serialized_booking(booking))

    @action(detail=True, methods=["post"])
    def checkout(self, request, pk=None):
        """Crée la transaction chez le prestataire : montant fixé par le serveur, lien de paiement renvoyé."""
        return checkout_response(self._get_booking(pk), request)

    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        """Paiement d'une réservation. Vérifie l'ownership ou le guest_token."""
        booking = self._get_booking(pk)
        payment_method = PaymentMethod.objects.filter(
            pk=request.data.get("payment_method"), active=True
        ).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable ou inactif."})

        actor = request.user if request.user.is_authenticated else None
        # La vérification du paiement (statut, montant, unicité) est faite par settle_booking_payment.
        try:
            settlement = settle_booking_payment(
                booking,
                payment_method=payment_method,
                actor=actor,
                external_reference=request.data.get("external_reference", ""),
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        if settlement.refund_due:
            return refund_due_response()
        booking = self.BASE_QUERYSET.get(pk=booking.pk)
        transactions = TransactionSerializer(
            settlement.transactions, many=True, context={"request": request}
        ).data
        return Response({"booking": self._serialized_booking(booking), "transactions": transactions})


class ClientParcelViewSet(viewsets.GenericViewSet):
    """
    Colis du client connecté.

    SÉCURITÉ :
    - Le client ne crée jamais de colis : c'est l'agence qui l'enregistre.
    - Seul un CLIENT authentifié peut consulter les colis rattachés à son compte.
    - Un COUNTER ou ADMIN obtient un 403 sur cette surface.
    - GET /parcels/{id}/ vérifie que le colis appartient au client (ownership).
    - Les actions internes (transition, assignation de trajet) ne sont pas exposées ici.
    """
    serializer_class = ParcelSerializer
    permission_classes = [IsClientOnly]

    def get_queryset(self):
        return Parcel.objects.select_related(
            "customer", "origin", "destination",
            "trip__route__origin", "trip__route__destination", "trip__vehicle"
        ).prefetch_related("status_history").filter(customer=self.request.user)

    def list(self, request):
        queryset = self.get_queryset()
        serializer = self.get_serializer(queryset, many=True)
        return Response({"count": queryset.count(), "results": serializer.data})

    def retrieve(self, request, pk=None):
        """
        Retourne un colis uniquement s'il appartient au client connecté.
        """
        parcel = get_object_or_404(self.get_queryset(), pk=pk)
        return Response(self.get_serializer(parcel).data)


class ClientRentalViewSet(viewsets.GenericViewSet):
    """
    Locations du client connecté.
    Seul un CLIENT authentifié peut créer ou consulter ses locations.
    """
    serializer_class = RentalBookingSerializer
    permission_classes = [IsClientOnly]

    def get_queryset(self):
        return RentalBooking.objects.select_related(
            "vehicle__base_location", "customer"
        ).filter(customer=self.request.user)

    def list(self, request):
        queryset = self.get_queryset()
        serializer = self.get_serializer(queryset, many=True)
        return Response({"count": queryset.count(), "results": serializer.data})

    def retrieve(self, request, pk=None):
        rental = get_object_or_404(self.get_queryset(), pk=pk)
        return Response(self.get_serializer(rental).data)

    def create(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(customer=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


# ─── Router ──────────────────────────────────────────────────────────────────

client_router = DefaultRouter()
client_router.register("locations", ClientLocationViewSet, basename="client-location")
client_router.register("trips", ClientTripViewSet, basename="client-trip")
client_router.register("seats", ClientSeatViewSet, basename="client-seat")
client_router.register("payment-methods", ClientPaymentMethodViewSet, basename="client-payment-method")
client_router.register("vehicles", ClientVehicleViewSet, basename="client-vehicle")
client_router.register("tickets", ClientTicketViewSet, basename="client-ticket")
client_router.register("bookings", ClientBookingViewSet, basename="client-booking")
client_router.register("parcels", ClientParcelViewSet, basename="client-parcel")
client_router.register("rentals", ClientRentalViewSet, basename="client-rental")

client_urlpatterns = [
    path("tickets/public/<str:reference>/", PublicTicketDetailView.as_view(), name="public-ticket-detail"),
    path("contact/", PublicContactView.as_view(), name="public-contact"),
    path("parcels/track/", ParcelTrackingView.as_view(), name="parcel-tracking"),
    path("webhooks/kkiapay/", KKiaPayWebhookView.as_view(), name="kkiapay-webhook"),
    path("webhooks/fedapay/", FedaPayWebhookView.as_view(), name="fedapay-webhook"),
    path("", include(client_router.urls)),
]
