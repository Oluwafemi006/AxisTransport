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
from types import SimpleNamespace
import hmac

from django.db import models
from django.core.cache import cache
from django.core.exceptions import ImproperlyConfigured, ValidationError as DjangoValidationError
from django.shortcuts import get_object_or_404
from django.urls import include, path
from rest_framework import status, viewsets
from django.conf import settings
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated

from .booking_limits import check_online_booking_limits
from rest_framework.response import Response
from rest_framework.routers import DefaultRouter
from rest_framework.views import APIView

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
from .payments import (
    ONLINE_PROVIDERS,
    SIMULATION,
    payment_quote,
    reconcile_pending_payments,
    settle_booking_payment,
    settle_ticket_payment,
)
from .services import (
    cancel_held_booking,
    hash_guest_token,
    is_plausible_phone,
    SEGMENT_CACHE_SECONDS,
    SEGMENT_DIRECTION_FORWARD,
    SEGMENT_DIRECTIONS,
    SegmentFareMissing,
    release_expired_holds,
    reserve_booking,
    segment_cache_key,
    segment_catalog,
    trip_fare,
    reserve_ticket,
    transition_parcel,
)
from .views import (
    FedaPayWebhookView,
    FrenchThrottleMixin,
    PaymentRefreshThrottle,
    KKiaPayWebhookView,
    ParcelTrackingView,
    PublicContactView,
    PublicTicketDetailView,
    TicketLookupView,
    BookingAddressThrottle,
    BookingPhoneThrottle,
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
    Ordonnés selon l'ordre de la ligne de car (1=Parakou, 2=Savè, ...), puis par nom.
    """
    queryset = Location.objects.filter(active=True).prefetch_related("boarding_points").order_by(
        models.F("line_stop__position").asc(nulls_last=True), "name"
    )
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
    pagination_class = None

    def get_queryset(self):
        from django.utils import timezone
        from datetime import datetime
        from .services import find_trips_for_waypoint_direction
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
        if origin or destination:
            queryset = find_trips_for_waypoint_direction(queryset, origin=origin, destination=destination)
        if date_value:
            try:
                selected_date = datetime.strptime(date_value, "%Y-%m-%d").date()
            except ValueError as exc:
                raise ValidationError({"date": "Format attendu : AAAA-MM-JJ."}) from exc
            queryset = queryset.filter(departure_at__date=selected_date)
        return queryset

    def list(self, request, *args, **kwargs):
        from .services import find_next_available_trip, require_segment_fare
        if request.query_params.get("origin") and request.query_params.get("destination"):
            try:
                require_segment_fare(request.query_params["origin"], request.query_params["destination"])
            except SegmentFareMissing as exc:
                raise exc.api_error()
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = self.get_serializer(queryset, many=True)
        data = serializer.data

        origin = request.query_params.get("origin")
        destination = request.query_params.get("destination")
        date_value = request.query_params.get("date")

        if origin or destination:
            next_available = None
            if len(data) == 0 and origin and destination:
                next_available = find_next_available_trip(
                    origin=origin, destination=destination, after_date=date_value
                )
            return Response({"results": data, "next_available": next_available})
        return Response(data)

    @action(detail=False, methods=["get"], url_path="banner")
    def banner(self, request):
        """Bandeau d'accueil dynamique construit côté serveur selon les voyages du jour et à venir."""
        from .services import build_homepage_banner
        return Response(build_homepage_banner())

    @action(detail=False, methods=["get"], url_path="search")
    def search(self, request):
        """Recherche directionnelle de trajets (/client/trips/search/?origin=...&destination=...&date=...)."""
        return self.list(request)

    @action(detail=True, methods=["get"], url_path="payment-quotes")
    def payment_quotes(self, request, pk=None):
        """
        Montant à payer AVANT toute réservation, par moyen de paiement en ligne actif :
        prix du billet (grille par tronçon) × nombre de passagers, plus les frais client (0 par défaut). Calculé ici, jamais dans le navigateur.
        Prend en compte l'origine et la destination de la recherche pour tarifer au tronçon exact si spécifié.
        """
        trip = self.get_object()
        try:
            passengers = int(request.query_params.get("passengers", 1))
        except ValueError as exc:
            raise ValidationError({"passengers": "Nombre de passagers invalide."}) from exc
        if not 1 <= passengers <= 8:
            raise ValidationError({"passengers": "Nombre de passagers invalide."})
        origin_val = request.query_params.get("origin")
        dest_val = request.query_params.get("destination")
        fare = None
        try:
            if origin_val and dest_val:
                from .services import require_segment_fare
                fare = require_segment_fare(origin_val, dest_val)
            if fare is None:
                fare = trip_fare(trip)
        except SegmentFareMissing as exc:
            raise exc.api_error()
        except ImproperlyConfigured as exc:
            raise ValidationError({"detail": str(exc)}) from exc
        target = SimpleNamespace(amount=fare.amount * passengers, currency=fare.currency)
        methods = [
            method
            for method in PaymentMethod.objects.filter(active=True).order_by("id")
            if method.code.upper() in ONLINE_PROVIDERS
            and (method.code.upper() != SIMULATION or (settings.DEBUG and settings.AXIS_PAYMENT_SIMULATION))
        ]
        return Response([payment_quote(target, method) for method in methods])


class ClientSegmentView(APIView):
    """Tronçons d'un sens pour l'accueil, lecture publique : calculés côté serveur, gardés 60 s."""

    permission_classes = [AllowAny]

    def get(self, request):
        direction = request.query_params.get("direction", SEGMENT_DIRECTION_FORWARD)
        if direction not in SEGMENT_DIRECTIONS:
            raise ValidationError({"direction": "Sens attendu : aller ou retour."})
        # « scope=all » (page de réservation du site) : tous les tronçons avec tarif, montée intermédiaire signalée.
        # Sans ce paramètre (accueil, app publiée) : montées au terminus seulement.
        scope_all = request.query_params.get("scope") == "all"
        key = segment_cache_key(direction) + (":all" if scope_all else "")
        payload = cache.get(key)
        if payload is None:
            payload = segment_catalog(direction, online=not scope_all)
            cache.set(key, payload, SEGMENT_CACHE_SECONDS)
        return Response(payload)


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
    # Indisponibles et en maintenance affichés (« rentable » faux, non demandables) ; archivés cachés.
    queryset = Vehicle.objects.filter(category=Vehicle.Category.RENTAL, archived=False)
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
            b_point = data.get("boarding_point_id")
            if b_point is None:
                b_point = data.get("boarding_point")
            a_point = data.get("alighting_point_id")
            if a_point is None:
                a_point = data.get("alighting_point")
            ticket = reserve_ticket(
                trip=data["trip"],
                seat=data["seat"],
                customer=request.user,
                passenger_name=data["passenger_name"],
                passenger_phone=data.get("passenger_phone", ""),
                channel=Ticket.Channel.ONLINE,  # Forcé : jamais COUNTER sur cette surface.
                origin=data.get("origin") or None,
                destination=data.get("destination") or None,
                boarding_point=b_point,
                alighting_point=a_point,
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


class ClientBookingViewSet(FrenchThrottleMixin, viewsets.GenericViewSet):
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

    def get_throttles(self):
        # Limites anti-abus seulement sur la création (pas sur la consultation ni le paiement).
        if self.action == "create":
            return [BookingAddressThrottle(), BookingPhoneThrottle()]
        return super().get_throttles()

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
            check_online_booking_limits(
                customer=customer, contact_phone=data.get("contact_phone", ""), seats=len(data["passengers"])
            )
            b_point = data.get("boarding_point_id")
            if b_point is None:
                b_point = data.get("boarding_point")
            a_point = data.get("alighting_point_id")
            if a_point is None:
                a_point = data.get("alighting_point")
            booking, guest_token = reserve_booking(
                trip=data["trip"],
                passengers=data["passengers"],
                customer=customer,
                contact_phone=data.get("contact_phone", ""),
                contact_email=data.get("contact_email", ""),
                buyer_ifu=data.get("buyer_ifu", ""),
                origin=data.get("origin"),
                destination=data.get("destination"),
                boarding_point=b_point,
                alighting_point=a_point,
                terminus_boarding_only=True,
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

    @action(detail=False, methods=["get"], url_path="mine")
    def mine(self, request):
        """
        « Mes réservations » : réservations du client connecté uniquement (En attente, Payée, Expirée, Annulée).
        """
        if not request.user.is_authenticated:
            raise PermissionDenied("Authentification requise pour consulter vos réservations.")
        if request.user.role != User.Role.CLIENT:
            raise PermissionDenied("Le personnel interne ne doit pas utiliser la surface client pour accéder aux réservations.")
        release_expired_holds()
        bookings = self.BASE_QUERYSET.filter(customer=request.user).order_by("-created_at")
        return Response(BookingSerializer(bookings, many=True, context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        """
        Annuler une réservation non payée et libérer ses sièges tout de suite.
        Réservé au propriétaire du compte ou au porteur du jeton de réservation (invité).
        """
        booking = self._get_booking(pk)
        try:
            booking, cancelled = cancel_held_booking(booking, actor=request.user if request.user.is_authenticated else None)
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response(self._serialized_booking(self.BASE_QUERYSET.get(pk=booking.pk), cancelled=cancelled))

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

    @action(detail=True, methods=["post"], url_path="refresh-payment", throttle_classes=[PaymentRefreshThrottle])
    def refresh_payment(self, request, pk=None):
        """
        « Vérifier mon paiement » : relit tout de suite chez FedaPay les transactions en cours de cette
        réservation, par le même chemin que le rattrapage automatique (montant exact, rattachement,
        une seule émission). Ne crée aucun paiement ; sans transaction en cours, ne fait rien.
        Réservé au propriétaire du compte ou au porteur du jeton de réservation (invité).
        """
        booking = self._get_booking(pk)
        reconcile_pending_payments(booking=booking)
        return Response(self._serialized_booking(self.BASE_QUERYSET.get(pk=booking.pk)))


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
    path("tickets/lookup/", TicketLookupView.as_view(), name="ticket-lookup"),
    path("contact/", PublicContactView.as_view(), name="public-contact"),
    path("segments/", ClientSegmentView.as_view(), name="client-segments"),
    path("parcels/track/", ParcelTrackingView.as_view(), name="parcel-tracking"),
    path("webhooks/kkiapay/", KKiaPayWebhookView.as_view(), name="kkiapay-webhook"),
    path("webhooks/fedapay/", FedaPayWebhookView.as_view(), name="fedapay-webhook"),
    path("", include(client_router.urls)),
]
