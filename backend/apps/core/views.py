import hashlib
import hmac
import json
import math
import re
from decimal import Decimal, InvalidOperation
from datetime import datetime
from types import SimpleNamespace

from django.conf import settings

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ImproperlyConfigured, ValidationError as DjangoValidationError
from django.db import DatabaseError, IntegrityError, transaction
from django.db.models import Count, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import AuthenticationFailed, PermissionDenied, Throttled, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView

from . import password_reset
from .models import (
    BoardingPoint,
    Booking,
    FareRule,
    FeatureFlag,
    Location,
    Parcel,
    ParcelPhoto,
    TripStopArrival,
    TicketControl,
    ParcelStatusHistory,
    PaymentMethod,
    RentalBooking,
    Route,
    Seat,
    SystemSetting,
    Ticket,
    TicketStatusHistory,
    AgencyProfile,
    AgencySettingChange,
    Tax,
    Transaction,
    Trip,
    User,
    Vehicle,
    PaymentIncident,
    PaymentReceipt,
    SegmentFare,
    SegmentFareChange,
    PasswordAdminReset,
    StaffInvitation,
    WeeklySchedule,
)
from .permissions import (
    IsAxisAdmin,
    IsClient,
    IsClientCounterOrAdmin,
    IsControllerOrAdmin,
    IsCounterOrAdmin,
    IsOperationsStaff,
)
from .serializers import (
    BoardingPointSerializer,
    PaymentIncidentSerializer,
    ManualTicketChangeSerializer,
    AgencyProfileSerializer,
    AgencySettingChangeSerializer,
    TaxSerializer,
    SegmentFareChangeSerializer,
    SegmentFareSerializer,
    BookingCreateSerializer,
    BookingSerializer,
    FareRuleSerializer,
    FeatureFlagSerializer,
    LocationSerializer,
    ParcelSerializer,
    PaymentMethodSerializer,
    PublicFeatureFlagSerializer,
    PublicPaymentMethodSerializer,
    PublicTicketDetailSerializer,
    PublicVehicleSerializer,
    RentalBookingSerializer,
    RouteSerializer,
    SeatSerializer,
    SystemSettingSerializer,
    TicketCreateSerializer,
    ControllerTicketSerializer,
    TicketSerializer,
    TransactionSerializer,
    TripSerializer,
    UserSerializer,
    VehicleSerializer,
    WeeklyScheduleSerializer,
)
from .payments import (
    ONLINE_PROVIDERS,
    REFUND_DUE_MESSAGE,
    SIMULATION,
    PaymentNotApproved,
    ProviderUnavailable,
    create_checkout,
    payment_quote,
    record_payment_incident,
    settle_booking_payment,
    settle_from_fedapay_webhook,
    settle_ticket_payment,
    verify_fedapay_signature,
)
from .photo_storage import upload_parcel_photo
from .services import (
    ReservationsClosed,
    SEGMENT_DIRECTION_FORWARD,
    SegmentFareMissing,
    confirm_trip_arrival,
    resolve_segment_fare,
    segment_catalog,
    cancel_held_booking,
    generate_alternating_trips,
    generate_trips_from_schedule,
    generate_trip_seats,
    hash_guest_token,
    release_expired_holds,
    reserve_booking,
    reserve_ticket,
    trip_fare,
    transition_parcel,
    update_segment_fare,
    transition_ticket,
    validate_ticket,
)


def service_validation_error(exc, *, staff=False):
    if isinstance(exc, SegmentFareMissing):
        return exc.api_error()
    # Réservations fermées (durée de blocage non saisie) : message sans texte technique, adapté au public.
    if isinstance(exc, ReservationsClosed):
        return ValidationError({"detail": ReservationsClosed.STAFF_MESSAGE if staff else ReservationsClosed.CLIENT_MESSAGE})
    # Statut du prestataire transmis tel quel, pour que les clients distinguent « en attente » d'un échec.
    if isinstance(exc, PaymentNotApproved):
        return ValidationError({"detail": exc.messages[0], "payment_status": exc.provider_status})
    if hasattr(exc, "message_dict"):
        return ValidationError(exc.message_dict)
    if hasattr(exc, "messages"):
        return ValidationError(exc.messages)
    return ValidationError(str(exc))


def refund_due_response():
    """Paiement reçu après expiration : reçu enregistré, aucun billet émis."""
    return Response({"detail": REFUND_DUE_MESSAGE, "refund_due": True}, status=status.HTTP_409_CONFLICT)


def checkout_response(target, request):
    payment_method = PaymentMethod.objects.filter(pk=request.data.get("payment_method"), active=True).first()
    if not payment_method:
        raise ValidationError({"payment_method": "Moyen de paiement introuvable ou inactif."})
    try:
        return Response(create_checkout(target, payment_method=payment_method))
    except DjangoValidationError as exc:
        raise service_validation_error(exc)


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    return Response({"status": "ok", "service": "axis-transport-api"})


CONTACT_SETTING_KEYS = ("contact_phone", "contact_whatsapp")


class PublicContactView(APIView):
    """Coordonnées publiques d'Axis, lues dans les réglages admin. Chaîne vide tant qu'elles ne sont pas renseignées."""

    permission_classes = [AllowAny]

    def get(self, request):
        values = dict(SystemSetting.objects.filter(key__in=CONTACT_SETTING_KEYS).values_list("key", "value"))
        return Response(
            {key: values[key].strip() if isinstance(values.get(key), str) else "" for key in CONTACT_SETTING_KEYS}
        )


# Étapes montrées au client. Les étapes internes de l'agence (dépôt, acceptation, affectation)
# restent regroupées sous « Enregistré ».
PARCEL_TRACKING_STEPS = [
    ("REGISTERED", "Enregistré", {"REGISTERED", "DEPOSITED", "ACCEPTED", "ASSIGNED"}),
    ("LOADED", "Chargé", {"LOADED"}),
    ("IN_TRANSIT", "En transit", {"IN_TRANSIT"}),
    ("ARRIVED", "Arrivé", {"ARRIVED"}),
    ("READY_FOR_PICKUP", "Disponible au retrait", {"READY_FOR_PICKUP"}),
    ("PICKED_UP", "Retiré", {"PICKED_UP"}),
]


class ParcelTrackingThrottle(SimpleRateThrottle):
    """Limite par adresse IP, connecté ou non : freine l'essai de codes en série."""

    scope = "parcel_tracking"

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class PublicTicketThrottle(SimpleRateThrottle):
    """Limite par adresse IP sur la page publique d'un billet : freine l'essai de références en série."""

    scope = "public_ticket"

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class ParcelTrackingView(APIView):
    """
    Suivi d'un colis par son code. Ne renvoie que le parcours, les étapes et les photos :
    aucun nom, téléphone ni description.
    """

    permission_classes = [AllowAny]
    throttle_classes = [ParcelTrackingThrottle]

    def get(self, request):
        code = str(request.query_params.get("code") or "").strip()
        if not code:
            raise ValidationError({"code": "Saisissez le code de suivi du colis."})
        parcel = (
            Parcel.objects.select_related("origin", "destination")
            .prefetch_related("status_history")
            .filter(tracking_number__iexact=code)
            .first()
        )
        if not parcel:
            return Response({"detail": "Aucun colis ne correspond à ce code."}, status=status.HTTP_404_NOT_FOUND)
        current = next(
            index for index, (_, _, statuses) in enumerate(PARCEL_TRACKING_STEPS) if parcel.status in statuses
        )
        history = list(parcel.status_history.all())
        steps = []
        for index, (key, label, statuses) in enumerate(PARCEL_TRACKING_STEPS):
            reached = [entry.changed_at for entry in history if entry.to_status in statuses]
            steps.append(
                {
                    "key": key,
                    "label": label,
                    "done": index <= current,
                    "current": index == current,
                    "reached_at": min(reached) if reached and index <= current else None,
                }
            )
        return Response(
            {
                "tracking_number": parcel.tracking_number,
                "origin": parcel.origin.name,
                "destination": parcel.destination.name,
                "current_step": PARCEL_TRACKING_STEPS[current][1],
                "steps": steps,
                "photos": [photo.url for photo in parcel.photos.all()],
            }
        )


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        """Le client complète ou corrige son e-mail (seul champ modifiable ici)."""
        user = request.user
        if user.role != User.Role.CLIENT:
            raise PermissionDenied("Votre e-mail se modifie par un administrateur.")
        if set(request.data) - {"email"}:
            raise ValidationError({"detail": "Seul l'e-mail peut être modifié ici."})
        serializer = UserSerializer(user, data={"email": request.data.get("email", "")}, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(UserSerializer(user).data)


class TooManyAttempts(Throttled):
    """Blocage temporaire, avec un message en français sans jargon ; l'en-tête Retry-After est conservé."""

    def __init__(self, wait):
        minutes = max(1, math.ceil(wait / 60)) if wait else 1
        super().__init__(
            wait=None,
            detail=f"Trop de tentatives, réessayez dans {minutes} minute{'s' if minutes > 1 else ''}.",
        )
        self.wait = math.ceil(wait) if wait else None


class _LiveRateThrottle(SimpleRateThrottle):
    """Seuil relu dans les réglages à chaque demande (et non figé au chargement du module)."""

    def get_rate(self):
        from rest_framework.settings import api_settings

        return api_settings.DEFAULT_THROTTLE_RATES.get(self.scope)


class _AddressThrottle(_LiveRateThrottle):
    """Par adresse IP (lue derrière le proxy selon AXIS_NUM_PROXIES)."""

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class LoginAddressThrottle(_AddressThrottle):
    scope = "login_address"


class RegisterAddressThrottle(_AddressThrottle):
    scope = "register_address"


class PaymentRefreshThrottle(_AddressThrottle):
    """« Vérifier mon paiement » : chaque demande interroge FedaPay, donc limitée par adresse IP."""

    scope = "payment_refresh"


class PasswordResetAddressThrottle(_AddressThrottle):
    scope = "password_reset_address"


class PasswordResetConfirmThrottle(_AddressThrottle):
    scope = "password_reset_confirm"


class PasswordResetEmailThrottle(_LiveRateThrottle):
    """Par adresse saisie, que le compte existe ou non : le blocage ne révèle donc rien."""

    scope = "password_reset_email"

    def get_cache_key(self, request, view):
        email = password_reset.normalize_email(request.data.get("email"))
        ident = hashlib.sha256(email.encode()).hexdigest()
        return self.cache_format % {"scope": self.scope, "ident": ident} if email else None


class BookingAddressThrottle(_AddressThrottle):
    scope = "booking_address"


class BookingPhoneThrottle(_LiveRateThrottle):
    """Créations de réservation par compte client, sinon par téléphone de contact normalisé."""

    scope = "booking_phone"

    def get_cache_key(self, request, view):
        from .booking_limits import normalize_phone

        if request.user.is_authenticated:
            ident = f"user-{request.user.pk}"
        else:
            phone = normalize_phone(request.data.get("contact_phone") if hasattr(request, "data") else "")
            if not phone:
                return None
            ident = hashlib.sha256(phone.encode()).hexdigest()
        return self.cache_format % {"scope": self.scope, "ident": ident}


class TicketLookupAddressThrottle(_AddressThrottle):
    scope = "ticket_lookup_address"


class TicketLookupReferenceThrottle(_LiveRateThrottle):
    scope = "ticket_lookup_reference"

    def get_cache_key(self, request, view):
        reference = str(request.data.get("reference") or "").strip().upper() if hasattr(request, "data") else ""
        if not reference:
            return None
        return self.cache_format % {"scope": self.scope, "ident": hashlib.sha256(reference.encode()).hexdigest()}


class LoginAccountThrottle(_LiveRateThrottle):
    """
    Échecs de connexion par identifiant saisi, comptés de deux façons :
    - par identifiant ET adresse ensemble (seuil « login_account_address ») : des échecs venus d'une autre
      adresse ne bloquent pas le titulaire du compte ;
    - par identifiant, toutes adresses confondues (seuil « login_account », plus haut) : plafond contre
      une attaque répartie sur de nombreuses adresses.
    Seules les tentatives ÉCHOUÉES comptent (enregistrées par la vue de connexion). Une connexion réussie
    efface les échecs de son adresse, pas ceux des autres. Au-delà d'un seuil, le blocage est temporaire et
    s'applique aussi au bon mot de passe. Une seule entrée de cache par identifiant : {adresse: [instants]}.
    """

    scope = "login_account_address"
    total_scope = "login_account"

    @staticmethod
    def key_for(username):
        ident = hashlib.sha256(str(username or "").strip().lower().encode()).hexdigest()
        return LoginAccountThrottle.cache_format % {"scope": LoginAccountThrottle.total_scope, "ident": ident}

    def get_cache_key(self, request, view):
        username = str(request.data.get("username") or "").strip() if hasattr(request, "data") else ""
        return self.key_for(username) if username else None

    def _total_rate(self):
        from rest_framework.settings import api_settings

        return api_settings.DEFAULT_THROTTLE_RATES.get(self.total_scope)

    def _limits(self):
        """(seuil par identifiant + adresse, plafond par identifiant) ; un seuil absent vaut (None, None)."""
        return self.parse_rate(self.get_rate()), self.parse_rate(self._total_rate())

    def _longest(self):
        return max((duration for _, duration in self._limits() if duration), default=0)

    def _load(self, key, now):
        data = self.cache.get(key)
        if not isinstance(data, dict):
            return {}
        longest = self._longest()
        kept = {}
        for address, moments in data.items():
            recent = [moment for moment in moments if moment > now - longest]
            if recent:
                kept[address] = recent
        return kept

    def allow_request(self, request, view):
        # Lecture seule : la demande n'est pas comptée ici.
        key = self.get_cache_key(request, view)
        if key is None or not self._longest():
            return True
        self.now = self.timer()
        data = self._load(key, self.now)
        pair, total = self._limits()
        checks = [
            (data.get(self.get_ident(request), []), pair),
            ([moment for moments in data.values() for moment in moments], total),
        ]
        for moments, (num_requests, duration) in checks:
            if num_requests is None:
                continue
            history = sorted((moment for moment in moments if moment > self.now - duration), reverse=True)
            if len(history) >= num_requests:
                # Valeurs lues par wait() pour l'en-tête Retry-After et le message.
                self.history, self.num_requests, self.duration = history, num_requests, duration
                return False
        return True

    def record_failure(self, request):
        key = self.get_cache_key(request, None)
        if key is None or not self._longest():
            return
        now = self.timer()
        data = self._load(key, now)
        data.setdefault(self.get_ident(request), []).insert(0, now)
        self.cache.set(key, data, self._longest())

    def reset(self, request):
        key = self.get_cache_key(request, None)
        if key is None:
            return
        data = self._load(key, self.timer())
        if data.pop(self.get_ident(request), None) is None:
            return
        if data:
            self.cache.set(key, data, self._longest())
        else:
            self.cache.delete(key)

    @classmethod
    def unblock(cls, username):
        """Efface tous les échecs d'un identifiant, toutes adresses (commande unblock_login)."""
        cls.cache.delete(cls.key_for(username))


class FrenchThrottleMixin:
    def throttled(self, request, wait):
        raise TooManyAttempts(wait)


class AxisTokenObtainPairView(FrenchThrottleMixin, TokenObtainPairView):
    """Connexion (jetons JWT). Réponse inchangée, sauf au-delà des seuils : 429 et message clair."""

    throttle_classes = [LoginAddressThrottle, LoginAccountThrottle]

    def post(self, request, *args, **kwargs):
        account = LoginAccountThrottle()
        try:
            response = super().post(request, *args, **kwargs)
        except (AuthenticationFailed, InvalidToken):
            # Identifiant ou mot de passe faux : seule cette tentative compte pour le blocage du compte.
            account.record_failure(request)
            raise
        if response.status_code == status.HTTP_200_OK:
            account.reset(request)
        return response


class RegisterView(FrenchThrottleMixin, APIView):
    permission_classes = [AllowAny]
    throttle_classes = [RegisterAddressThrottle]

    def post(self, request):
        payload = request.data.copy()
        payload["role"] = User.Role.CLIENT
        serializer = UserSerializer(data=payload)
        serializer.is_valid(raise_exception=True)
        user = serializer.save(role=User.Role.CLIENT)
        return Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


class PasswordChangeThrottle(_LiveRateThrottle):
    """Essais du mot de passe actuel, par compte connecté."""

    scope = "password_change"

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": request.user.pk}


class PasswordChangeView(FrenchThrottleMixin, APIView):
    """Changement par le titulaire : les autres sessions sont fermées, celle-ci reçoit de nouveaux jetons."""

    permission_classes = [IsAuthenticated]
    throttle_classes = [PasswordChangeThrottle]

    def post(self, request):
        user = request.user
        if not user.check_password(str(request.data.get("current_password") or "")):
            return Response(
                {"current_password": ["Mot de passe actuel incorrect."]}, status=status.HTTP_400_BAD_REQUEST
            )
        password = str(request.data.get("new_password") or "")
        try:
            validate_password(password, user)
        except DjangoValidationError as error:
            return Response({"new_password": error.messages}, status=status.HTTP_400_BAD_REQUEST)
        password_reset.change_password(user, password)
        refresh = RefreshToken.for_user(user)
        return Response({"detail": "Mot de passe modifié.", "access": str(refresh.access_token), "refresh": str(refresh)})


class PasswordResetRequestView(FrenchThrottleMixin, APIView):
    """Demande de code : réponse identique que le compte existe ou non."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [PasswordResetAddressThrottle, PasswordResetEmailThrottle]

    def post(self, request):
        password_reset.request_code(request.data.get("email"))
        return Response({"detail": password_reset.REQUEST_MESSAGE})


class PasswordResetConfirmView(FrenchThrottleMixin, APIView):
    """Saisie du code et du nouveau mot de passe, puis fermeture de toutes les sessions."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [PasswordResetConfirmThrottle]

    def post(self, request):
        password = str(request.data.get("password") or "")
        # Contrôlé avant le code : cette erreur ne dit rien sur l'adresse ou le code.
        try:
            validate_password(password)
        except DjangoValidationError as error:
            return Response({"password": error.messages}, status=status.HTTP_400_BAD_REQUEST)
        done = password_reset.confirm_code(request.data.get("email"), request.data.get("code"), password)
        if not done:
            return Response({"detail": password_reset.INVALID_MESSAGE}, status=status.HTTP_400_BAD_REQUEST)
        return Response({"detail": "Mot de passe modifié. Connectez-vous avec le nouveau."})


class AcceptStaffInvitationView(FrenchThrottleMixin, APIView):
    """
    Activation de compte suite à une invitation d'un membre du personnel.
    GET  : vérifie la validité du token pour affichage dans le formulaire web.
    POST : valide le token, crée l'utilisateur avec is_active=True, is_staff=True,
           l'ajoute au groupe prévu, définit son mot de passe et marque l'invitation comme utilisée.
    """

    permission_classes = [AllowAny]
    throttle_classes = [RegisterAddressThrottle]

    def get(self, request):
        token_str = request.query_params.get("token") or request.data.get("token")
        if not token_str:
            return Response({"error": "Le jeton d'invitation est manquant."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            invitation = StaffInvitation.objects.select_related("group").get(token=token_str)
        except (StaffInvitation.DoesNotExist, ValueError, DjangoValidationError):
            return Response({"error": "Ce lien d'invitation est invalide ou inexistant."}, status=status.HTTP_404_NOT_FOUND)

        if invitation.is_used:
            return Response({"error": "Cette invitation a déjà été utilisée."}, status=status.HTTP_400_BAD_REQUEST)
        if invitation.expires_at <= timezone.now():
            return Response({"error": "Cette invitation a expiré. Veuillez contacter un administrateur."}, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            "valid": True,
            "email": invitation.email,
            "group": invitation.group.name,
        })

    def post(self, request):
        token_str = request.data.get("token")
        password = request.data.get("password")

        if not token_str:
            return Response({"error": "Le jeton d'invitation est obligatoire."}, status=status.HTTP_400_BAD_REQUEST)
        if not password:
            return Response({"error": "Le mot de passe est obligatoire."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            invitation = StaffInvitation.objects.select_related("group").get(token=token_str)
        except (StaffInvitation.DoesNotExist, ValueError, DjangoValidationError):
            return Response({"error": "Ce lien d'invitation est invalide ou inexistant."}, status=status.HTTP_404_NOT_FOUND)

        if invitation.is_used:
            return Response({"error": "Cette invitation a déjà été utilisée."}, status=status.HTTP_400_BAD_REQUEST)
        if invitation.expires_at <= timezone.now():
            return Response({"error": "Cette invitation a expiré. Veuillez contacter un administrateur."}, status=status.HTTP_400_BAD_REQUEST)

        # Validation de robustesse du mot de passe
        try:
            validate_password(password)
        except DjangoValidationError as e:
            return Response({"error": " ".join(e.messages)}, status=status.HTTP_400_BAD_REQUEST)

        # Correspondance groupe -> rôle métier User
        group_name = invitation.group.name
        role_mapping = {
            "Guichetier": User.Role.COUNTER,
            "Contrôleur": User.Role.CONTROLLER,
            "Superviseur": User.Role.ADMIN,
        }
        role = role_mapping.get(group_name, User.Role.COUNTER)

        username = invitation.email
        # Si un utilisateur existe déjà avec cet email ou username
        user = User.objects.filter(Q(username=username) | Q(email=invitation.email)).first()
        if user:
            user.email = invitation.email
            user.set_password(password)
            user.role = role
            user.is_staff = True
            user.is_active = True
            user.save()
        else:
            user = User.objects.create_user(
                username=username,
                email=invitation.email,
                password=password,
                role=role,
                is_staff=True,
                is_active=True,
            )

        # Ajout au groupe Django prévu
        user.groups.add(invitation.group)

        # Marquer l'invitation comme utilisée
        invitation.is_used = True
        invitation.save(update_fields=["is_used"])

        return Response({
            "success": True,
            "message": "Votre compte AXIS Transport a été activé avec succès.",
            "username": user.username,
            "email": user.email,
            "role": user.role,
            "role_display": user.get_role_display(),
            "group": invitation.group.name,
        }, status=status.HTTP_200_OK)


class PublicReadAdminWriteMixin:
    def get_permissions(self):
        if self.action in {"list", "retrieve"}:
            if self.request.query_params.get("all") == "true":
                return [IsAxisAdmin()]
            return [AllowAny()]
        return [IsAxisAdmin()]


class LocationViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = Location.objects.prefetch_related("boarding_points")
    serializer_class = LocationSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(active=True)
        return queryset


class BoardingPointViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    """
    Points d'embarquement et de débarquement par ville.
    Lecture publique des points actifs (?all=true réservé à l'ADMIN).
    Création, modification et activation/désactivation réservées à l'ADMIN.
    Suppression refusée si le point a déjà été utilisé sur une réservation ou un billet.
    """

    queryset = BoardingPoint.objects.select_related("location").order_by("location__name", "order", "name")
    serializer_class = BoardingPointSerializer
    pagination_class = None

    def get_queryset(self):
        queryset = super().get_queryset()
        location_id = self.request.query_params.get("location")
        if location_id:
            queryset = queryset.filter(location_id=location_id)
        if self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(active=True, location__active=True)
        return queryset

    def perform_destroy(self, instance):
        if (
            instance.bookings_as_boarding_point.exists()
            or instance.bookings_as_alighting_point.exists()
            or instance.tickets_as_boarding_point.exists()
            or instance.tickets_as_alighting_point.exists()
        ):
            raise ValidationError(
                {"detail": "Ce point d'embarquement a déjà servi sur un billet ou une réservation : désactivez-le au lieu de le supprimer."}
            )
        super().perform_destroy(instance)


class RouteViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = Route.objects.select_related("origin", "destination")
    serializer_class = RouteSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(active=True)
        return queryset


class VehicleViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = Vehicle.objects.select_related("base_location")
    serializer_class = VehicleSerializer

    def get_serializer_class(self):
        if self.action in {"list", "retrieve"} and not (
            self.request.user.is_authenticated and self.request.user.role == User.Role.ADMIN
        ):
            return PublicVehicleSerializer
        return VehicleSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        category = self.request.query_params.get("category")
        state_value = self.request.query_params.get("state")
        if category:
            queryset = queryset.filter(category=category)
        if state_value:
            queryset = queryset.filter(state=state_value)
        return queryset

    @action(detail=True, methods=["post"], url_path="sync-future-seats")
    def sync_future_seats(self, request, pk=None):
        vehicle = self.get_object()
        if not vehicle.seat_labels:
            raise ValidationError("Configurez la capacité ou le plan de sièges avant la synchronisation.")
        trips = vehicle.trips.filter(departure_at__gte=timezone.now()).exclude(status=Trip.Status.CANCELLED)
        synced = 0
        for trip in trips:
            if not trip.tickets.exists():
                trip.seats.all().delete()
                generate_trip_seats(trip)
                synced += 1
        return Response({"synced_trips": synced})


class TripViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = Trip.objects.select_related("route__origin", "route__destination", "vehicle").prefetch_related("seats")
    serializer_class = TripSerializer

    def get_permissions(self):
        if self.action in {"list", "retrieve"}:
            if self.request.query_params.get("all") == "true":
                return [IsOperationsStaff()]
            return [AllowAny()]
        return [IsAxisAdmin()]

    def get_queryset(self):
        release_expired_holds()
        queryset = super().get_queryset()
        origin = self.request.query_params.get("origin")
        destination = self.request.query_params.get("destination")
        date_value = self.request.query_params.get("date")
        status_value = self.request.query_params.get("status")
        if origin or destination:
            from .services import find_trips_for_waypoint_direction
            queryset = find_trips_for_waypoint_direction(queryset, origin=origin, destination=destination)
        if date_value:
            try:
                selected_date = datetime.strptime(date_value, "%Y-%m-%d").date()
            except ValueError as exc:
                raise ValidationError({"date": "Format attendu : AAAA-MM-JJ."}) from exc
            queryset = queryset.filter(departure_at__date=selected_date)
        if status_value:
            queryset = queryset.filter(status=status_value)
        elif self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(
                status__in=[Trip.Status.SCHEDULED, Trip.Status.BOARDING], departure_at__gte=timezone.now()
            )
        return queryset

    def perform_create(self, serializer):
        trip = serializer.save()
        if trip.vehicle.seat_labels:
            generate_trip_seats(trip)

    @action(detail=False, methods=["get"], url_path="search")
    def search(self, request):
        """Recherche directionnelle de trajets (/trips/search/?origin=...&destination=...&date=...)."""
        return self.list(request)

    @action(detail=False, methods=["post"], url_path="generate")
    def generate(self, request):
        """
        Planning quotidien en sens alterné (administrateur) : parcours du premier jour, bus, date de début,
        nombre de jours, heure de départ. Voir services.generate_alternating_trips.
        """
        data = request.data
        route = Route.objects.filter(pk=data.get("route")).select_related("origin", "destination").first()
        if route is None:
            raise ValidationError({"route": "Choisissez le parcours du premier jour."})
        vehicle = Vehicle.objects.filter(pk=data.get("vehicle"), category=Vehicle.Category.BUS).first()
        if vehicle is None:
            raise ValidationError({"vehicle": "Choisissez un bus."})
        try:
            start_date = datetime.strptime(str(data.get("start_date") or ""), "%Y-%m-%d").date()
        except ValueError as exc:
            raise ValidationError({"start_date": "Date de début invalide (format AAAA-MM-JJ)."}) from exc
        try:
            departure_time = datetime.strptime(str(data.get("departure_time") or ""), "%H:%M").time()
        except ValueError as exc:
            raise ValidationError({"departure_time": "Heure de départ invalide (format HH:MM)."}) from exc
        try:
            days = int(data.get("days"))
        except (TypeError, ValueError) as exc:
            raise ValidationError({"days": "Nombre de jours invalide."}) from exc
        try:
            created, skipped = generate_alternating_trips(
                route=route, vehicle=vehicle, start_date=start_date, days=days, departure_time=departure_time
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response(
            {"created": len(created), "trips": TripSerializer(created, many=True, context={"request": request}).data, "skipped": skipped},
            status=status.HTTP_201_CREATED,
        )

    def perform_update(self, serializer):
        old_vehicle = serializer.instance.vehicle
        trip = serializer.save()
        if trip.vehicle != old_vehicle and trip.vehicle.seat_labels:
            if not trip.seats.filter(status__in=[Seat.Status.BOOKED, Seat.Status.HELD]).exists():
                trip.seats.all().delete()
                generate_trip_seats(trip)


class WeeklyScheduleViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = WeeklySchedule.objects.select_related("route__origin", "route__destination", "vehicle").all()
    serializer_class = WeeklyScheduleSerializer
    pagination_class = None

    def get_permissions(self):
        if self.action in {"list", "retrieve"}:
            if self.request.query_params.get("all") == "true":
                return [IsOperationsStaff()]
            return [AllowAny()]
        return [IsAxisAdmin()]

    @action(detail=False, methods=["post"], url_path="generate-trips")
    def generate_trips(self, request):
        """Génère les trajets réels pour les prochaines semaines à partir du planning par défaut."""
        try:
            weeks = int(request.data.get("weeks", 4))
        except (TypeError, ValueError):
            weeks = 4
        created = generate_trips_from_schedule(weeks=weeks)
        return Response(
            {
                "created": len(created),
                "trips": TripSerializer(created, many=True, context={"request": request}).data,
            },
            status=status.HTTP_201_CREATED,
        )


class SeatViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Seat.objects.select_related("trip")
    serializer_class = SeatSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        release_expired_holds()
        queryset = super().get_queryset()
        trip = self.request.query_params.get("trip")
        return queryset.filter(trip_id=trip) if trip else queryset.none()


class FareRuleViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = FareRule.objects.select_related("route__origin", "route__destination")
    serializer_class = FareRuleSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        route = self.request.query_params.get("route")
        if route:
            queryset = queryset.filter(route_id=route)
        if self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(active=True)
        return queryset


class FeatureFlagViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = FeatureFlag.objects.all()
    serializer_class = FeatureFlagSerializer

    def get_serializer_class(self):
        if self.action in {"list", "retrieve"} and not (
            self.request.user.is_authenticated and self.request.user.role == User.Role.ADMIN
        ):
            return PublicFeatureFlagSerializer
        return FeatureFlagSerializer


class SystemSettingViewSet(viewsets.ModelViewSet):
    queryset = SystemSetting.objects.all()
    serializer_class = SystemSettingSerializer
    permission_classes = [IsAxisAdmin]


class SegmentFareViewSet(mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """
    Grille des prix par tronçon : lecture et modification du prix, administrateur uniquement.
    Ni création ni suppression ici : les tronçons sont chargés par « load_segment_fares ».
    """

    queryset = SegmentFare.objects.select_related("start__location", "end__location", "updated_by")
    serializer_class = SegmentFareSerializer
    permission_classes = [IsAxisAdmin]
    http_method_names = ["get", "patch", "head", "options"]
    pagination_class = None

    @action(detail=False, methods=["get"], url_path="missing")
    def missing(self, request):
        """Tronçons sans tarif : un tarif vaut pour les deux sens, un seul sens suffit."""
        return Response(segment_catalog(SEGMENT_DIRECTION_FORWARD)["missing_fares"])

    def partial_update(self, request, *args, **kwargs):
        if set(request.data.keys()) - {"amount"}:
            raise ValidationError({"detail": "Seul le prix d'un tronçon peut être modifié."})
        if "amount" not in request.data:
            raise ValidationError({"amount": "Indiquez le nouveau prix."})
        try:
            fare, changed = update_segment_fare(self.get_object(), request.data["amount"], actor=request.user)
        except DjangoValidationError as exc:
            raise ValidationError({"amount": exc.messages})
        data = self.get_serializer(self.get_queryset().get(pk=fare.pk)).data
        return Response({**data, "changed": changed})

    def update(self, request, *args, **kwargs):
        if not kwargs.get("partial"):
            raise ValidationError({"detail": "Utilisez une modification partielle du prix."})
        return super().update(request, *args, **kwargs)


class SegmentFareChangeViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Journal des modifications de prix de tronçon, en lecture seule, administrateur uniquement."""

    queryset = SegmentFareChange.objects.select_related("fare__start__location", "fare__end__location", "changed_by")
    serializer_class = SegmentFareChangeSerializer
    permission_classes = [IsAxisAdmin]


class BusPositionView(APIView):
    """Dernières arrivées confirmées par les contrôleurs : c'est la notification de l'agence."""

    permission_classes = [IsAxisAdmin]

    def get(self, request):
        arrivals = TripStopArrival.objects.select_related("trip__route__origin", "trip__route__destination", "location", "confirmed_by")[:30]
        return Response(
            [
                {
                    "id": arrival.id,
                    "route": str(arrival.trip.route),
                    "departure_at": arrival.trip.departure_at,
                    "stop": arrival.location.name,
                    "final": arrival.location_id == arrival.trip.route.destination_id,
                    "confirmed_at": arrival.confirmed_at,
                    "confirmed_by": (arrival.confirmed_by.get_full_name() or arrival.confirmed_by.username) if arrival.confirmed_by else "",
                }
                for arrival in arrivals
            ]
        )


class AgencyProfileView(APIView):
    """Page « Agence et taxes » : informations de l'agence, administrateur uniquement, chaque modification journalisée."""

    permission_classes = [IsAxisAdmin]

    def get(self, request):
        return Response(AgencyProfileSerializer(AgencyProfile.current()).data)

    @transaction.atomic
    def patch(self, request):
        profile = AgencyProfile.objects.select_for_update().get(pk=AgencyProfile.current().pk)
        before = {field: getattr(profile, field) for field in AgencyProfile.EDITABLE_FIELDS}
        serializer = AgencyProfileSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        after = {**before, **serializer.validated_data}
        if after != before:
            serializer.save(updated_by=request.user)
            AgencySettingChange.objects.create(
                kind=AgencySettingChange.Kind.AGENCY,
                label="Informations de l'agence",
                old_value=before,
                new_value=after,
                changed_by=request.user,
            )
        return Response(AgencyProfileSerializer(profile).data)


class TaxViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """Taxes des billets : administrateur uniquement, sans suppression (désactiver à la place), journalisées."""

    queryset = Tax.objects.all()
    serializer_class = TaxSerializer
    permission_classes = [IsAxisAdmin]
    http_method_names = ["get", "post", "patch", "head", "options"]

    @staticmethod
    def _snapshot(tax):
        return {"name": tax.name, "rate": str(tax.rate), "active": tax.active, "included": tax.included}

    def perform_create(self, serializer):
        tax = serializer.save(updated_by=self.request.user)
        AgencySettingChange.objects.create(
            kind=AgencySettingChange.Kind.TAX,
            label=f"Taxe {tax.name}",
            old_value=None,
            new_value=self._snapshot(tax),
            changed_by=self.request.user,
        )

    def perform_update(self, serializer):
        before = self._snapshot(serializer.instance)
        tax = serializer.save(updated_by=self.request.user)
        after = self._snapshot(tax)
        if after != before:
            AgencySettingChange.objects.create(
                kind=AgencySettingChange.Kind.TAX,
                label=f"Taxe {tax.name}",
                old_value=before,
                new_value=after,
                changed_by=self.request.user,
            )


class AgencySettingChangeViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Journal de la page « Agence et taxes », en lecture seule, administrateur uniquement."""

    queryset = AgencySettingChange.objects.select_related("changed_by")
    serializer_class = AgencySettingChangeSerializer
    permission_classes = [IsAxisAdmin]


class ManualTicketChangeViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Journal des statuts de billet forcés à la main, en lecture seule, administrateur uniquement."""

    queryset = (
        TicketStatusHistory.objects.filter(manual=True).select_related("ticket", "changed_by").order_by("-changed_at")
    )
    serializer_class = ManualTicketChangeSerializer
    permission_classes = [IsAxisAdmin]


class PaymentIncidentViewSet(mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """Incidents de paiement : liste et case « traité », réservés à l'administrateur. Ni création ni suppression."""

    queryset = PaymentIncident.objects.select_related("booking").all()
    serializer_class = PaymentIncidentSerializer
    permission_classes = [IsAxisAdmin]
    http_method_names = ["get", "patch", "head", "options"]


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("role", "first_name", "last_name", "username")
    serializer_class = UserSerializer
    permission_classes = [IsAxisAdmin]

    def perform_update(self, serializer):
        password_changed = "password" in serializer.validated_data
        user = serializer.save()
        if password_changed:
            PasswordAdminReset.objects.create(target=user, actor=self.request.user)

    @action(detail=True, methods=["post"], url_path="reset-password")
    def reset_password(self, request, pk=None):
        """Seule voie pour le personnel et les clients sans e-mail ; journalisée, sessions fermées."""
        user = self.get_object()
        password = str(request.data.get("password") or "")
        try:
            validate_password(password, user)
        except DjangoValidationError as error:
            return Response({"password": error.messages}, status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            password_reset.change_password(user, password)
            PasswordAdminReset.objects.create(target=user, actor=request.user)
        return Response({"detail": f"Mot de passe de {user.username} modifié."})


class TicketViewSet(viewsets.ModelViewSet):
    queryset = Ticket.objects.select_related(
        "customer", "seat", "trip__route__origin", "trip__route__destination", "trip__vehicle"
    ).prefetch_related("status_history", "controls")
    serializer_class = TicketSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        release_expired_holds()
        queryset = super().get_queryset()
        if self.request.user.role == User.Role.CLIENT:
            queryset = queryset.filter(customer=self.request.user)
        trip = self.request.query_params.get("trip")
        if self.request.user.role == User.Role.CONTROLLER and not trip:
            return queryset.none()
        if trip:
            queryset = queryset.filter(trip_id=trip)
        return queryset

    def get_permissions(self):
        # Les actions ayant leurs propres règles d'accès les gardent : cette méthode remplace
        # sinon celles déclarées sur l'action (défaut corrigé : scan et changement d'état ouverts à tout compte).
        if self.action == "validate_qr":
            return [IsControllerOrAdmin()]
        if self.action == "transition":
            return [IsAxisAdmin()]
        # Vente et encaissement : client connecté (ses propres billets), guichet ou admin.
        if self.action in {"create", "pay"}:
            return [IsClientCounterOrAdmin()]
        if self.action in {"update", "partial_update", "destroy"}:
            return [IsAxisAdmin()]
        return [IsAuthenticated()]

    def get_serializer_class(self):
        if self.action == "create":
            return TicketCreateSerializer
        if self.request.user.is_authenticated and self.request.user.role == User.Role.CONTROLLER:
            return ControllerTicketSerializer
        return TicketSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        
        if request.user.is_authenticated and request.user.role == User.Role.CLIENT:
            customer = request.user
            channel = Ticket.Channel.ONLINE
        elif request.user.is_authenticated and request.user.role in {User.Role.COUNTER, User.Role.ADMIN}:
            customer_id = request.data.get("customer")
            customer = User.objects.filter(pk=customer_id, role=User.Role.CLIENT).first() if customer_id else None
            channel = Ticket.Channel.COUNTER
        else:
            raise PermissionDenied("Ce rôle ne permet pas de vendre un billet.")
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
                customer=customer,
                passenger_name=data["passenger_name"],
                passenger_phone=data.get("passenger_phone", ""),
                channel=channel,
                origin=data.get("origin") or None,
                destination=data.get("destination") or None,
                boarding_point=b_point,
                alighting_point=a_point,
                # Un client achète en ligne : montée au terminus seulement ; le guichet garde tous les arrêts.
                terminus_boarding_only=request.user.role == User.Role.CLIENT,
            )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc, staff=request.user.role in {User.Role.COUNTER, User.Role.ADMIN})
        return Response(TicketSerializer(ticket, context={"request": request}).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        ticket = self.get_object()
        payment_method = PaymentMethod.objects.filter(pk=request.data.get("payment_method")).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable."})
        actor = request.user if request.user.is_authenticated else None
        try:
            settlement = settle_ticket_payment(
                ticket,
                payment_method=payment_method,
                actor=actor,
                external_reference=request.data.get("external_reference", ""),
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        if settlement.refund_due:
            return refund_due_response()
        return Response(
            {
                "ticket": TicketSerializer(settlement.target).data,
                "transaction": TransactionSerializer(settlement.transactions[0]).data,
            }
        )

    @action(detail=True, methods=["post"], permission_classes=[IsAxisAdmin])
    def transition(self, request, pk=None):
        # Changement de statut forcé à la main : administrateur uniquement, inscrit au journal
        # (aucun écran ne s'en sert ; la vente passe par « pay » ou /staff/sales/, qui créent un paiement).
        try:
            ticket = transition_ticket(
                self.get_object(),
                request.data.get("status"),
                actor=request.user,
                note=request.data.get("note", ""),
                manual=True,
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response(TicketSerializer(ticket).data)

    @action(detail=False, methods=["post"], permission_classes=[IsControllerOrAdmin], url_path="validate-qr")
    def validate_qr(self, request):
        token_or_reference = request.data.get("qr_token") or request.data.get("reference")
        if request.data.get("reference") and not request.data.get("qr_token"):
            matched_ticket = Ticket.objects.filter(reference=request.data["reference"]).only("qr_token").first()
            if not matched_ticket:
                raise ValidationError({"reference": "Ticket introuvable."})
            token_or_reference = matched_ticket.qr_token
        expected_trip = None
        if request.data.get("trip"):
            expected_trip = Trip.objects.filter(pk=request.data["trip"]).first()
            if not expected_trip:
                raise ValidationError({"trip": "Voyage introuvable."})
        try:
            ticket, control = validate_ticket(
                qr_token=token_or_reference,
                controller=request.user,
                expected_trip=expected_trip,
                method=request.data.get("method", "QR"),
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response({"ticket": self.get_serializer(ticket).data, "control_id": control.id})


class BookingViewSet(viewsets.ModelViewSet):
    queryset = Booking.objects.select_related(
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
    serializer_class = BookingSerializer

    def get_permissions(self):
        # Route interne : la réservation invitée n'existe que sur /api/v1/client/.
        if self.action in {"create", "pay"}:
            return [IsClientCounterOrAdmin()]
        if self.action in {"update", "partial_update", "destroy"}:
            return [IsAxisAdmin()]
        return [IsAuthenticated()]

    def get_serializer_class(self):
        if self.action == "create":
            return BookingCreateSerializer
        return BookingSerializer

    def get_queryset(self):
        release_expired_holds()
        queryset = super().get_queryset()
        user = self.request.user
        if not user.is_authenticated:
            return queryset.none()
        if user.role == User.Role.CLIENT:
            queryset = queryset.filter(customer=user)
        elif not user.is_axis_staff:
            return queryset.none()
        status_param = self.request.query_params.get("status")
        if status_param:
            queryset = queryset.filter(status=status_param)
        return queryset

    def _guest_token(self):
        return self.request.headers.get("X-Booking-Token") or self.request.data.get("guest_token", "")

    def _assert_can_access(self, booking):
        user = self.request.user
        if user.is_authenticated and (booking.customer_id == user.id or user.is_axis_staff):
            return
        token = self._guest_token()
        if booking.guest_token_hash and token and hmac.compare_digest(
            booking.guest_token_hash,
            hash_guest_token(token),
        ):
            return
        raise PermissionDenied("Accès à la réservation refusé.")

    def get_object(self):
        booking = get_object_or_404(self.queryset, pk=self.kwargs["pk"])
        self._assert_can_access(booking)
        return booking

    def _serialized_booking(self, booking, request, **extra):
        payload = BookingSerializer(booking, context={"request": request}).data
        payload.update(extra)
        return payload

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = request.user
        customer = user if user.is_authenticated and user.role == User.Role.CLIENT else None
        try:
            b_point = data.get("boarding_point_id")
            if b_point is None:
                b_point = data.get("boarding_point")
            a_point = data.get("alighting_point_id")
            if a_point is None:
                a_point = data.get("alighting_point")
            if not (request.user.is_authenticated and request.user.is_axis_staff):
                from .booking_limits import check_online_booking_limits

                check_online_booking_limits(
                    customer=customer, contact_phone=data.get("contact_phone", ""), seats=len(data["passengers"])
                )
            booking, guest_token = reserve_booking(
                trip=data["trip"],
                passengers=data["passengers"],
                customer=customer,
                contact_phone=data.get("contact_phone", ""),
                contact_email=data.get("contact_email", ""),
                buyer_ifu=data.get("buyer_ifu", ""),
                origin=data.get("origin") or None,
                destination=data.get("destination") or None,
                boarding_point=b_point,
                alighting_point=a_point,
                # Un client achète en ligne : montée au terminus seulement ; le personnel garde tous les arrêts.
                terminus_boarding_only=not (request.user.is_authenticated and request.user.is_axis_staff),
            )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc, staff=request.user.is_authenticated and request.user.role != User.Role.CLIENT)
        booking = self.queryset.get(pk=booking.pk)
        extra = {"guest_access_token": guest_token} if guest_token else {}
        return Response(
            self._serialized_booking(booking, request, **extra),
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        booking = self.get_object()
        payment_method = PaymentMethod.objects.filter(pk=request.data.get("payment_method"), active=True).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable ou inactif."})
        actor = request.user if request.user.is_authenticated else None
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
        booking = self.queryset.get(pk=booking.pk)
        transactions = TransactionSerializer(
            settlement.transactions, many=True, context={"request": request}
        ).data
        return Response({"booking": self._serialized_booking(booking, request), "transactions": transactions})


class ParcelViewSet(viewsets.ModelViewSet):
    queryset = Parcel.objects.select_related(
        "customer", "origin", "destination", "trip__route__origin", "trip__route__destination", "trip__vehicle"
    ).prefetch_related("status_history")
    serializer_class = ParcelSerializer
    permission_classes = [IsClientCounterOrAdmin]

    def get_permissions(self):
        # Le client ne crée jamais de colis : l'agence (guichet ou admin) l'enregistre.
        if self.action in {"create", "update", "partial_update", "destroy", "transition"}:
            return [IsCounterOrAdmin()]
        return [IsClientCounterOrAdmin()]

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.request.user.role == User.Role.CLIENT:
            queryset = queryset.filter(customer=self.request.user)
        tracking = self.request.query_params.get("tracking_number")
        return queryset.filter(tracking_number=tracking) if tracking else queryset

    def perform_create(self, serializer):
        is_client = self.request.user.role == User.Role.CLIENT
        parcel = serializer.save(
            customer=self.request.user if is_client else None,
            channel=Ticket.Channel.ONLINE if is_client else Ticket.Channel.COUNTER,
        )
        ParcelStatusHistory.objects.create(
            parcel=parcel, to_status=Parcel.Status.REGISTERED, changed_by=self.request.user
        )

    @action(detail=True, methods=["post"], permission_classes=[IsCounterOrAdmin])
    def price(self, request, pk=None):
        """Gros colis : l'agence fixe le prix ; l'ancien et le nouveau montant restent à l'historique."""
        parcel = self.get_object()
        amount = str(request.data.get("amount") or "")
        if not amount.isdigit() or int(amount) <= 0:
            raise ValidationError({"amount": "Saisissez un prix entier en FCFA, supérieur à zéro."})
        old = parcel.amount
        parcel.amount = int(amount)
        parcel.save(update_fields=["amount", "updated_at"])
        ParcelStatusHistory.objects.create(
            parcel=parcel, from_status=parcel.status, to_status=parcel.status, changed_by=request.user,
            note=f"Prix : {old} → {amount} FCFA",
        )
        return Response(ParcelSerializer(parcel).data)

    @action(detail=True, methods=["post"], permission_classes=[IsCounterOrAdmin])
    def transition(self, request, pk=None):
        parcel = self.get_object()
        if "trip" in request.data:
            parcel.trip_id = request.data.get("trip")
            parcel.save(update_fields=["trip", "updated_at"])
        if "pickup_recipient_identity" in request.data:
            parcel.pickup_recipient_identity = request.data["pickup_recipient_identity"]
            parcel.save(update_fields=["pickup_recipient_identity", "updated_at"])
        try:
            parcel = transition_parcel(
                parcel, request.data.get("status"), actor=request.user, note=request.data.get("note", "")
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response(ParcelSerializer(parcel).data)


class RentalBookingViewSet(viewsets.ModelViewSet):
    queryset = RentalBooking.objects.select_related("vehicle__base_location", "customer")
    serializer_class = RentalBookingSerializer
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            return [IsClient()]
        if self.action in {"update", "partial_update", "destroy"}:
            return [IsAxisAdmin()]
        return [IsAuthenticated()]

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.request.user.role == User.Role.CLIENT:
            return queryset.filter(customer=self.request.user)
        if self.request.user.role == User.Role.ADMIN:
            return queryset
        return queryset.none()

    def perform_create(self, serializer):
        serializer.save(customer=self.request.user)


class PaymentMethodViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = PaymentMethod.objects.all()
    serializer_class = PaymentMethodSerializer

    def get_serializer_class(self):
        if self.action in {"list", "retrieve"} and not (
            self.request.user.is_authenticated and self.request.user.role == User.Role.ADMIN
        ):
            return PublicPaymentMethodSerializer
        return PaymentMethodSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(active=True)
        return queryset


class TransactionViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Transaction.objects.select_related("payment_method", "ticket", "parcel", "rental")
    serializer_class = TransactionSerializer
    permission_classes = [IsCounterOrAdmin]


class DashboardView(APIView):
    permission_classes = [IsAxisAdmin]

    def get(self, request):
        start_raw = request.query_params.get("start")
        end_raw = request.query_params.get("end")
        try:
            start = datetime.fromisoformat(start_raw).date() if start_raw else timezone.localdate()
            end = datetime.fromisoformat(end_raw).date() if end_raw else start
        except ValueError as exc:
            raise ValidationError("Les dates doivent respecter le format AAAA-MM-JJ.") from exc

        tickets = Ticket.objects.filter(created_at__date__range=(start, end))
        transactions = Transaction.objects.filter(
            status=Transaction.Status.SUCCEEDED, created_at__date__range=(start, end)
        )
        trips = Trip.objects.filter(departure_at__date__range=(start, end)).annotate(
            revenue=Sum("tickets__transactions__amount", filter=Q(tickets__transactions__status=Transaction.Status.SUCCEEDED)),
            sold=Count("tickets", filter=Q(tickets__status__in=[Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CHECKED, Ticket.Status.COMPLETED]), distinct=True),
            checked=Count("tickets", filter=Q(tickets__status__in=[Ticket.Status.CHECKED, Ticket.Status.COMPLETED]), distinct=True),
        )
        return Response(
            {
                "period": {"start": start, "end": end},
                "tickets": {
                    "sold": tickets.exclude(
                        status__in=[Ticket.Status.HELD, Ticket.Status.EXPIRED, Ticket.Status.CANCELLED]
                    ).count(),
                    "online": tickets.filter(channel=Ticket.Channel.ONLINE).count(),
                    "counter": tickets.filter(channel=Ticket.Channel.COUNTER).count(),
                    "checked": tickets.filter(status__in=[Ticket.Status.CHECKED, Ticket.Status.COMPLETED]).count(),
                    "cancelled_or_refunded": tickets.filter(
                        status__in=[Ticket.Status.CANCELLED, Ticket.Status.REFUNDED]
                    ).count(),
                },
                "parcels": list(
                    Parcel.objects.filter(created_at__date__range=(start, end))
                    .values("status")
                    .annotate(count=Count("id"))
                    .order_by("status")
                ),
                "revenue": {
                    "total": transactions.aggregate(total=Sum("amount"))["total"] or 0,
                    "by_payment_method": list(
                        transactions.values("payment_method__label").annotate(total=Sum("amount"))
                    ),
                },
                "trips": [
                    {
                        "id": trip.id,
                        "label": str(trip),
                        "sold": trip.sold,
                        "checked": trip.checked,
                        "capacity": trip.vehicle.capacity,
                        "revenue": trip.revenue or 0,
                    }
                    for trip in trips.select_related("route__origin", "route__destination", "vehicle")
                ],
            }
        )

class KKiaPayWebhookView(APIView):
    """KKiaPay n'est pas implémenté : le webhook refuse tout et n'émet jamais de billet."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        return Response(
            {"error": "Le paiement KKiaPay est désactivé."}, status=status.HTTP_503_SERVICE_UNAVAILABLE
        )


class FedaPayWebhookView(APIView):
    """
    Webhook FedaPay. La signature est obligatoire ; la transaction est ensuite revérifiée
    auprès de l'API FedaPay, et la réservation est déduite des données vérifiées, jamais de la requête.
    """

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        if not settings.FEDAPAY_WEBHOOK_SECRET:
            return Response({"error": "Webhook FedaPay non configuré."}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        signature = request.headers.get("X-FEDAPAY-SIGNATURE", "")
        if not signature:
            return Response({"error": "Signature absente."}, status=status.HTTP_400_BAD_REQUEST)
        raw_body = request.body
        try:
            verify_fedapay_signature(
                raw_body,
                signature,
                settings.FEDAPAY_WEBHOOK_SECRET,
                tolerance=settings.FEDAPAY_WEBHOOK_TOLERANCE_SECONDS,
            )
        except DjangoValidationError:
            return Response({"error": "Signature invalide."}, status=status.HTTP_400_BAD_REQUEST)

        # À partir d'ici le message est authentique. Un refus définitif répond 200 (FedaPay désactive le webhook
        # après 10 essais sans réponse 2xx) et laisse une trace durable ; une erreur passagère répond 503
        # pour que FedaPay réessaie.
        try:
            event = json.loads(raw_body)
        except ValueError:
            return self._refused(reason="Corps du message illisible.")
        entity = event.get("entity") if isinstance(event, dict) else None
        if not isinstance(entity, dict) or entity.get("status") != "approved":
            return Response({"message": "Événement ignoré."}, status=status.HTTP_200_OK)
        event_name = event.get("name", "")
        transaction_id = entity.get("id")
        if not transaction_id:
            return self._refused(reason="Identifiant de transaction manquant.", event=event_name, entity=entity)

        try:
            settlement = settle_from_fedapay_webhook(transaction_id)
        except ProviderUnavailable as exc:
            return Response({"error": exc.messages}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        except DatabaseError:
            return Response({"error": "Base de données indisponible."}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        except DjangoValidationError as exc:
            return self._refused(
                reason=" ".join(str(message) for message in exc.messages),
                event=event_name,
                entity=entity,
                proof=getattr(exc, "proof", None),
                booking=getattr(exc, "booking", None),
            )
        return Response(
            {
                "status": "REFUND_DUE" if settlement.refund_due else "SUCCESS",
                "booking_id": settlement.target.pk,
                "tickets_issued": len(settlement.tickets),
                "already_processed": not settlement.created,
            },
            status=status.HTTP_200_OK,
        )

    def _refused(self, *, reason, event="", entity=None, proof=None, booking=None):
        """Refus définitif d'un message authentique : enregistré pour l'administrateur, puis accusé de réception."""
        entity = entity or {}
        amount = proof.amount if proof else None
        if amount is None:
            try:
                amount = Decimal(str(entity.get("amount")))
            except (InvalidOperation, TypeError):
                amount = None
        currency = entity.get("currency")
        try:
            incident = record_payment_incident(
                source=PaymentIncident.Source.WEBHOOK,
                reason=reason,
                event=event,
                external_id=entity.get("id") or "",
                amount=amount,
                currency=proof.currency if proof else (currency.get("iso", "") if isinstance(currency, dict) else ""),
                verified=proof is not None,
                booking=booking,
            )
        except DatabaseError:
            # Sans trace durable, on ne prétend pas avoir traité : FedaPay réessaiera.
            return Response({"error": "Base de données indisponible."}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        return Response({"status": "REFUSED", "incident": incident.pk, "reason": reason}, status=status.HTTP_200_OK)


class StaffTicketViewSet(viewsets.GenericViewSet):
    """
    Gestion des billets par le staff (CONTROLLER ou ADMIN).
    Surface API : /api/v1/staff/
    """
    serializer_class = ControllerTicketSerializer
    permission_classes = [IsControllerOrAdmin]

    def get_queryset(self):
        # Le staff peut consulter tous les billets
        from .models import Ticket
        return Ticket.objects.select_related(
            "customer", "seat", "trip__route__origin",
            "trip__route__destination", "trip__vehicle"
        ).prefetch_related("status_history", "controls")

    @action(detail=False, methods=["post"])
    def validate(self, request):
        """
        Scanne et valide un billet via son QR code (qr_token).
        Accessible uniquement aux contrôleurs.
        """
        qr_token = request.data.get("qr_token")
        if not qr_token:
            return Response({"error": "Le paramètre 'qr_token' est requis."}, status=status.HTTP_400_BAD_REQUEST)

        # Le contrôleur peut optionnellement passer l'ID du trajet prévu pour vérifier que c'est le bon bus
        expected_trip_id = request.data.get("expected_trip_id")
        expected_trip = None
        if expected_trip_id:
            from .models import Trip
            try:
                expected_trip = Trip.objects.get(pk=expected_trip_id)
            except Trip.DoesNotExist:
                return Response({"error": "Le trajet attendu est introuvable."}, status=status.HTTP_400_BAD_REQUEST)

        from .services import validate_ticket
        from .models import TicketControl
        try:
            # actor = controller (request.user)
            ticket, control = validate_ticket(
                qr_token=qr_token,
                controller=request.user,
                expected_trip=expected_trip,
                method=TicketControl.Method.QR,
            )
        except DjangoValidationError as exc:
            # Retourne un 400 clair pour que l'app mobile lise l'erreur (Billet déjà scanné, etc.)
            return Response({"error": exc.messages if hasattr(exc, "messages") else str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            "status": "SUCCESS",
            "ticket": self.get_serializer(ticket).data,
            "control_id": control.pk,
            "message": "Billet validé avec succès."
        })

    @action(detail=False, methods=["post"], permission_classes=[IsCounterOrAdmin])
    def sell_counter(self, request):
        """
        Vente au guichet (COUNTER ou ADMIN) : le tarif vient de FareRule, l'encaissement
        passe par le même chemin que tout autre paiement et crée reçu + transaction.
        """
        passenger_name = str(request.data.get("passenger_name") or "").strip()
        if not request.data.get("trip_id") or not request.data.get("seat_id") or not passenger_name:
            raise ValidationError("trip_id, seat_id et passenger_name sont requis.")
        trip = Trip.objects.filter(pk=request.data.get("trip_id")).first()
        if not trip:
            raise ValidationError({"trip_id": "Trajet introuvable."})
        if trip.departure_at < timezone.now():
            raise ValidationError("Impossible de vendre un billet pour un trajet passé.")
        seat = Seat.objects.filter(pk=request.data.get("seat_id"), trip=trip).first()
        if not seat:
            raise ValidationError({"seat_id": "Siège introuvable pour ce trajet."})
        payment_method = PaymentMethod.objects.filter(pk=request.data.get("payment_method"), active=True).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable ou inactif."})

        origin = request.data.get("origin")
        destination = request.data.get("destination")
        boarding_point = request.data.get("boarding_point_id")
        if boarding_point is None:
            boarding_point = request.data.get("boarding_point")
        alighting_point = request.data.get("alighting_point_id")
        if alighting_point is None:
            alighting_point = request.data.get("alighting_point")

        try:
            with transaction.atomic():
                booking, _ = reserve_booking(
                    trip=trip,
                    passengers=[
                        {
                            "full_name": passenger_name,
                            "phone": str(request.data.get("passenger_phone") or ""),
                            "seat": seat,
                        }
                    ],
                    channel=Ticket.Channel.COUNTER,
                    origin=origin,
                    destination=destination,
                    boarding_point=boarding_point,
                    alighting_point=alighting_point,
                )
                settlement = settle_booking_payment(
                    booking,
                    payment_method=payment_method,
                    actor=request.user,
                    external_reference=request.data.get("external_reference", ""),
                )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc, staff=True)
        ticket, payment = settlement.tickets[0], settlement.transactions[0]
        return Response(
            {
                "status": "SUCCESS",
                "ticket_reference": ticket.reference,
                "qr_token": str(ticket.qr_token),
                "amount": ticket.amount,
                "currency": ticket.currency,
                "transaction_reference": payment.reference,
            },
            status=status.HTTP_201_CREATED,
        )


_SALE_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


class StaffSaleViewSet(viewsets.GenericViewSet):
    """
    Vente d'un billet par un agent (guichet, contrôleur, administrateur) depuis l'application staff.
    Surface API : /api/v1/staff/sales/

    Le serveur décide de tout : tarif lu en base, place tenue sous verrou, billet émis seulement après
    encaissement attesté (espèces) ou paiement vérifié auprès du prestataire (Mobile Money).
    Chaque vente porte une clé envoyée par l'application : un nouvel essai ne crée jamais de seconde réservation.
    """

    permission_classes = [IsOperationsStaff]
    queryset = Booking.objects.select_related("trip__route__origin", "trip__route__destination", "trip__vehicle")

    def _payload(self, booking, **extra):
        booking = Booking.objects.prefetch_related("passengers", "tickets__seat", "tickets__trip__route").get(pk=booking.pk)
        return {"booking": BookingSerializer(booking, context={"request": self.request}).data, **extra}

    def _own_sale(self, pk):
        """Une vente n'est accessible qu'à l'agent qui l'a faite (ou à un administrateur)."""
        booking = get_object_or_404(Booking, pk=pk, sold_by__isnull=False)
        if booking.sold_by_id != self.request.user.id and self.request.user.role != User.Role.ADMIN:
            raise PermissionDenied("Cette vente a été faite par un autre agent.")
        return booking

    def _payment_method(self, value):
        payment_method = PaymentMethod.objects.filter(pk=value, active=True).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable ou inactif."})
        return payment_method

    def _sellable_trips(self):
        release_expired_holds()
        trips = Trip.objects.select_related("route__origin", "route__destination", "vehicle").filter(
            route__active=True, status__in=[Trip.Status.SCHEDULED, Trip.Status.BOARDING]
        )
        today = timezone.localdate()
        if self.request.user.role == User.Role.CONTROLLER:
            # Le contrôleur vend sur les départs du jour (vente à l'arrêt, y compris après l'heure de départ).
            return trips.filter(departure_at__date=today)
        return trips.filter(departure_at__gte=timezone.now())

    @action(detail=False, methods=["get"])
    def options(self, request):
        """Départs vendables par cet agent, avec places restantes et montant à encaisser par moyen de paiement."""
        methods = list(PaymentMethod.objects.filter(active=True).order_by("id"))
        methods = [
            method
            for method in methods
            if method.code.upper() != SIMULATION or (settings.DEBUG and settings.AXIS_PAYMENT_SIMULATION)
        ]
        trips = []
        for trip in self._sellable_trips().order_by("departure_at"):
            item = TripSerializer(trip, context={"request": request}).data
            try:
                fare = trip_fare(trip)
            except ImproperlyConfigured:
                # Aucun tarif en base : le départ est affiché mais non vendable, sans prix de repli.
                item["quotes"] = []
            else:
                target = SimpleNamespace(amount=fare.amount, currency=fare.currency)
                item["quotes"] = [
                    {**payment_quote(target, method), "online": method.code.upper() in ONLINE_PROVIDERS}
                    for method in methods
                ]
            # Vente en route : tous les tronçons du départ dans le sens du bus ; sans tarif, pas de tronçon.
            item["arrivals"] = list(trip.stop_arrivals.values_list("location_id", flat=True))
            item["segments"] = []
            stops = trip.route.get_stops_sequence()
            for index, start in enumerate(stops):
                for end in stops[index + 1:]:
                    try:
                        fare = resolve_segment_fare(start, end)
                    except SegmentFareMissing:
                        continue
                    target = SimpleNamespace(amount=fare.amount, currency=fare.currency)
                    item["segments"].append(
                        {
                            "origin_id": start.pk,
                            "origin": start.name,
                            "destination_id": end.pk,
                            "destination": end.name,
                            "quotes": [
                                {**payment_quote(target, method), "online": method.code.upper() in ONLINE_PROVIDERS}
                                for method in methods
                            ],
                        }
                    )
            trips.append(item)
        base = SystemSetting.objects.filter(key="parcel_base_price_fcfa").first()
        return Response({"trips": trips, "parcel_base_fcfa": base.value if base else None})

    @action(detail=False, methods=["get"], url_path="parcels")
    def parcels(self, request):
        """Colis enregistrés par cet agent, les plus récents d'abord."""
        ids = ParcelStatusHistory.objects.filter(
            changed_by=request.user, to_status=Parcel.Status.REGISTERED
        ).values("parcel_id")
        rows = Parcel.objects.filter(pk__in=ids).select_related("origin", "destination").prefetch_related("photos")[:50]
        return Response(
            [
                {
                    "tracking_number": parcel.tracking_number,
                    "route": f"{parcel.origin.name} → {parcel.destination.name}",
                    "description": parcel.description,
                    "status": parcel.get_status_display(),
                    "amount": parcel.amount,
                    "photos": [photo.url for photo in parcel.photos.all()],
                }
                for parcel in rows
            ]
        )

    @action(detail=False, methods=["post"], url_path="parcel")
    def parcel(self, request):
        """Colis enregistré par un agent, avec 1 à 3 photos obligatoires."""
        photos = request.FILES.getlist("photos")
        if not 1 <= len(photos) <= 3:
            raise ValidationError({"photos": "Ajoutez 1 à 3 photos du colis."})
        serializer = ParcelSerializer(
            data={key: request.data.get(key) for key in (
                "sender_name", "sender_phone", "recipient_name", "recipient_phone", "origin", "destination", "description"
            )}
        )
        serializer.is_valid(raise_exception=True)
        # Envoi avant la transaction : une base ne doit pas rester verrouillée pendant un appel réseau.
        try:
            stored = [upload_parcel_photo(photo) for photo in photos]
        except DjangoValidationError as exc:
            raise service_validation_error(exc, staff=True)
        with transaction.atomic():
            # Prix de base réglé par l'admin ; sans réglage, l'agence le fixe ensuite.
            base = SystemSetting.objects.filter(key="parcel_base_price_fcfa").first()
            parcel = serializer.save(channel=Ticket.Channel.COUNTER, amount=base.value if base else None)
            ParcelPhoto.objects.bulk_create(
                ParcelPhoto(parcel=parcel, url=url, public_id=public_id) for url, public_id in stored
            )
            ParcelStatusHistory.objects.create(
                parcel=parcel, to_status=Parcel.Status.REGISTERED, changed_by=request.user
            )
        return Response(
            {"tracking_number": parcel.tracking_number, "amount": parcel.amount, "photos": [url for url, _ in stored]},
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=["post"])
    def arrival(self, request):
        """Le contrôleur confirme l'arrivée du bus à un arrêt : l'agence voit la position dans /admin."""
        trip = self._sellable_trips().filter(pk=request.data.get("trip")).first()
        if not trip:
            raise ValidationError({"trip": "Ce départ n'est pas en cours pour cet agent."})
        stop = request.data.get("stop")
        if not str(stop).isdigit():
            raise ValidationError({"stop": "Arrêt requis."})
        try:
            arrival = confirm_trip_arrival(trip, int(stop), actor=request.user)
        except DjangoValidationError as exc:
            raise service_validation_error(exc, staff=True)
        return Response({"stop": arrival.location.name, "confirmed_at": arrival.confirmed_at})

    @action(detail=False, methods=["get"])
    def summary(self, request):
        """Activité du jour de l'agent connecté : calculée ici, jamais dans l'application."""
        today = timezone.localdate()
        payments = Transaction.objects.filter(
            ticket__booking__sold_by=request.user, status=Transaction.Status.SUCCEEDED, created_at__date=today
        ).select_related("payment_method")
        cash = mobile_money = Decimal("0")
        for payment in payments:
            if payment.payment_method.code.upper() in ONLINE_PROVIDERS:
                mobile_money += payment.amount
            else:
                cash += payment.amount
        return Response(
            {
                "scanned_tickets": TicketControl.objects.filter(
                    controller=request.user, controlled_at__date=today, result=TicketControl.Result.ACCEPTED
                ).count(),
                "sold_tickets": payments.values("ticket").distinct().count(),
                "parcels": ParcelStatusHistory.objects.filter(
                    changed_by=request.user, changed_at__date=today, to_status=Parcel.Status.REGISTERED
                ).count(),
                "cash_fcfa": int(cash),
                "mobile_money_fcfa": int(mobile_money),
            }
        )

    @action(detail=False, methods=["post"])
    def sell(self, request):
        """
        Vend un billet. Espèces : l'agent atteste avoir reçu l'argent, le billet est émis tout de suite.
        Mobile Money : la place est tenue, la transaction est créée chez le prestataire ; le billet n'est émis
        qu'après vérification (action « verify »).
        Rejouer la même demande avec la même clé reprend la vente en cours au lieu d'en créer une autre.
        """
        key = str(request.data.get("idempotency_key") or "").strip()
        if not _SALE_KEY_PATTERN.match(key):
            raise ValidationError({"idempotency_key": "Clé de vente absente ou invalide."})
        payment_method = self._payment_method(request.data.get("payment_method"))
        online = payment_method.code.upper() in ONLINE_PROVIDERS

        booking = Booking.objects.filter(sold_by=request.user, idempotency_key=key).first()
        created = booking is None
        try:
            with transaction.atomic():
                if booking is None:
                    passenger_name = str(request.data.get("passenger_name") or "").strip()
                    if not passenger_name:
                        raise ValidationError({"passenger_name": "Le nom du passager est requis."})
                    trip_id, seat_id = request.data.get("trip"), request.data.get("seat")
                    if not str(trip_id).isdigit() or not str(seat_id).isdigit():
                        raise ValidationError("Le départ et le siège sont requis.")
                    trip = self._sellable_trips().filter(pk=trip_id).first()
                    if not trip:
                        raise ValidationError({"trip": "Ce départ n'est pas vendable par cet agent."})
                    seat = Seat.objects.filter(pk=seat_id, trip=trip).first()
                    if not seat:
                        raise ValidationError({"seat": "Siège introuvable pour ce départ."})
                    origin = request.data.get("origin")
                    destination = request.data.get("destination")
                    boarding_point = request.data.get("boarding_point_id")
                    if boarding_point is None:
                        boarding_point = request.data.get("boarding_point")
                    alighting_point = request.data.get("alighting_point_id")
                    if alighting_point is None:
                        alighting_point = request.data.get("alighting_point")
                    booking, _ = reserve_booking(
                        trip=trip,
                        passengers=[
                            {
                                "full_name": passenger_name,
                                "phone": str(request.data.get("passenger_phone") or "").strip(),
                                "seat": seat,
                            }
                        ],
                        contact_phone=str(request.data.get("passenger_phone") or "").strip(),
                        channel=Ticket.Channel.COUNTER,
                        sold_by=request.user,
                        idempotency_key=key,
                        # Le contrôleur vend à l'arrêt, y compris après l'heure (départs du jour : _sellable_trips).
                        allow_departed=request.user.role == User.Role.CONTROLLER,
                        buyer_ifu=str(request.data.get("buyer_ifu") or ""),
                        origin=origin,
                        destination=destination,
                        boarding_point=boarding_point,
                        alighting_point=alighting_point,
                    )
                # Espèces : réservation et émission dans la même transaction, donc jamais de billet à moitié créé.
                if not online and booking.status == Booking.Status.HELD:
                    settle_booking_payment(booking, payment_method=payment_method, actor=request.user)
        except IntegrityError:
            # Deux envois simultanés de la même clé : le second reprend la vente créée par le premier.
            booking = Booking.objects.filter(sold_by=request.user, idempotency_key=key).first()
            if booking is None:
                raise ValidationError("Vente impossible, réessayez.")
            created = False
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc, staff=True)

        booking.refresh_from_db()
        checkout = None
        if online and booking.status == Booking.Status.HELD:
            try:
                checkout = create_checkout(booking, payment_method=payment_method)
            except DjangoValidationError as exc:
                # La place reste tenue : l'application réessaie avec la même clé, sans seconde réservation.
                return Response(
                    self._payload(booking, checkout=None, created=created, payment_error=" ".join(exc.messages)),
                    status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
                )
        return Response(
            self._payload(booking, checkout=checkout, created=created),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @action(detail=True, methods=["post"])
    def verify(self, request, pk=None):
        """Mobile Money : demande au serveur de vérifier le paiement auprès du prestataire et d'émettre le billet."""
        booking = self._own_sale(pk)
        payment_method = self._payment_method(request.data.get("payment_method"))
        if payment_method.code.upper() not in ONLINE_PROVIDERS:
            raise ValidationError({"payment_method": "La vérification ne concerne que les paiements en ligne."})
        try:
            settlement = settle_booking_payment(
                booking,
                payment_method=payment_method,
                actor=request.user,
                external_reference=request.data.get("external_reference", ""),
                source=PaymentReceipt.Source.COUNTER,
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        if settlement.refund_due:
            return refund_due_response()
        return Response(self._payload(booking))

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        """Annule une vente non payée et libère la place."""
        booking = self._own_sale(pk)
        try:
            booking, cancelled = cancel_held_booking(booking, actor=request.user)
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response(self._payload(booking, cancelled=cancelled))

    def retrieve(self, request, pk=None):
        """État d'une vente (place tenue, payée, expirée)."""
        release_expired_holds()
        return Response(self._payload(self._own_sale(pk)))


class PublicTicketDetailView(APIView):
    """
    Vue publique non-authentifiée de consultation d'un billet via sa référence unique.
    GET /api/v1/client/tickets/public/<reference>/
    """
    permission_classes = [AllowAny]
    throttle_classes = [PublicTicketThrottle]

    def get(self, request, reference):
        ticket = get_object_or_404(
            Ticket.objects.select_related(
                "trip__route__origin",
                "trip__route__destination",
                "seat",
                "customer"
            ),
            reference__iexact=reference.strip()
        )
        serializer = PublicTicketDetailSerializer(ticket, context={"request": request})
        return Response(serializer.data)



class TicketLookupView(FrenchThrottleMixin, APIView):
    """
    « Retrouver mon billet » : référence + téléphone utilisé à l'achat (passager ou contact).
    Renvoie seulement la référence ; même refus que la référence existe ou non.
    """

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [TicketLookupAddressThrottle, TicketLookupReferenceThrottle]
    NOT_FOUND = "Aucun billet ne correspond à cette référence et à ce numéro."

    def post(self, request):
        from .booking_limits import normalize_phone

        reference = str(request.data.get("reference") or "").strip()
        phone = normalize_phone(request.data.get("phone"))
        ticket = Ticket.objects.select_related("booking").filter(reference__iexact=reference).first() if reference else None
        phones = set()
        if ticket is not None:
            phones = {normalize_phone(ticket.passenger_phone)}
            if ticket.booking_id:
                phones.add(normalize_phone(ticket.booking.contact_phone))
            phones.discard("")
        if not phone or phone not in phones:
            return Response({"detail": self.NOT_FOUND}, status=status.HTTP_404_NOT_FOUND)
        return Response({"reference": ticket.reference})
