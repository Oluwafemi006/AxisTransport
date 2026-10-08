import hmac
from datetime import datetime

from django.core.exceptions import ImproperlyConfigured, ValidationError as DjangoValidationError
from django.db.models import Count, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import (
    Booking,
    FareRule,
    FeatureFlag,
    Location,
    Parcel,
    ParcelStatusHistory,
    PaymentMethod,
    RentalBooking,
    Route,
    Seat,
    SystemSetting,
    Ticket,
    Transaction,
    Trip,
    User,
    Vehicle,
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
)
from .services import (
    generate_trip_seats,
    hash_guest_token,
    pay_and_issue_booking,
    pay_and_issue_ticket,
    release_expired_holds,
    reserve_booking,
    reserve_ticket,
    transition_parcel,
    transition_ticket,
    validate_ticket,
)


def service_validation_error(exc):
    if hasattr(exc, "message_dict"):
        return ValidationError(exc.message_dict)
    if hasattr(exc, "messages"):
        return ValidationError(exc.messages)
    return ValidationError(str(exc))


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    return Response({"status": "ok", "service": "axis-transport-api"})


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)


class RegisterView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        payload = request.data.copy()
        payload["role"] = User.Role.CLIENT
        serializer = UserSerializer(data=payload)
        serializer.is_valid(raise_exception=True)
        user = serializer.save(role=User.Role.CLIENT)
        return Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


class PublicReadAdminWriteMixin:
    def get_permissions(self):
        if self.action in {"list", "retrieve"}:
            if self.request.query_params.get("all") == "true":
                return [IsAxisAdmin()]
            return [AllowAny()]
        return [IsAxisAdmin()]


class LocationViewSet(PublicReadAdminWriteMixin, viewsets.ModelViewSet):
    queryset = Location.objects.all()
    serializer_class = LocationSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.action == "list" and self.request.query_params.get("all") != "true":
            queryset = queryset.filter(active=True)
        return queryset


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


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("role", "first_name", "last_name", "username")
    serializer_class = UserSerializer
    permission_classes = [IsAxisAdmin]


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
        if self.action in {"create", "pay"}:
            return [AllowAny()]
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
        elif request.user.is_authenticated and request.user.role == User.Role.CONTROLLER:
            raise ValidationError("Le rôle contrôleur ne permet pas de vendre un billet.")
        else:
            # Guest checkout
            customer = None
            channel = Ticket.Channel.ONLINE
        try:
            ticket = reserve_ticket(
                trip=data["trip"],
                seat=data["seat"],
                customer=customer,
                passenger_name=data["passenger_name"],
                passenger_phone=data.get("passenger_phone", ""),
                channel=channel,
            )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc)
        return Response(TicketSerializer(ticket, context={"request": request}).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        if request.user.is_authenticated and request.user.role == User.Role.CONTROLLER:
            raise ValidationError("Le rôle contrôleur ne permet pas d'enregistrer un paiement.")
        ticket = self.get_object()
        payment_method = PaymentMethod.objects.filter(pk=request.data.get("payment_method")).first()
        if not payment_method:
            raise ValidationError({"payment_method": "Moyen de paiement introuvable."})
        actor = request.user if request.user.is_authenticated else None
        try:
            ticket, payment = pay_and_issue_ticket(
                ticket,
                payment_method=payment_method,
                actor=actor,
                external_reference=request.data.get("external_reference", ""),
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        return Response({"ticket": TicketSerializer(ticket).data, "transaction": TransactionSerializer(payment).data})

    @action(detail=True, methods=["post"], permission_classes=[IsOperationsStaff])
    def transition(self, request, pk=None):
        if request.user.role == User.Role.CONTROLLER and request.data.get("status") != Ticket.Status.COMPLETED:
            raise ValidationError("Le contrôleur peut uniquement clôturer un voyage déjà contrôlé.")
        try:
            ticket = transition_ticket(
                self.get_object(), request.data.get("status"), actor=request.user, note=request.data.get("note", "")
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
        if self.action in {"create", "retrieve", "pay"}:
            return [AllowAny()]
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
            return queryset.filter(customer=user)
        if user.is_axis_staff:
            return queryset
        return queryset.none()

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
            booking, guest_token = reserve_booking(
                trip=data["trip"],
                passengers=data["passengers"],
                customer=customer,
                contact_phone=data.get("contact_phone", ""),
                contact_email=data.get("contact_email", ""),
            )
        except (DjangoValidationError, ImproperlyConfigured) as exc:
            raise service_validation_error(exc)
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
            booking, _, payments = pay_and_issue_booking(
                booking,
                payment_method=payment_method,
                actor=actor,
                external_reference=request.data.get("external_reference", ""),
            )
        except DjangoValidationError as exc:
            raise service_validation_error(exc)
        booking = self.queryset.get(pk=booking.pk)
        transactions = TransactionSerializer(payments, many=True, context={"request": request}).data
        return Response({"booking": self._serialized_booking(booking, request), "transactions": transactions})


class ParcelViewSet(viewsets.ModelViewSet):
    queryset = Parcel.objects.select_related(
        "customer", "origin", "destination", "trip__route__origin", "trip__route__destination", "trip__vehicle"
    ).prefetch_related("status_history")
    serializer_class = ParcelSerializer
    permission_classes = [IsClientCounterOrAdmin]

    def get_permissions(self):
        if self.action in {"update", "partial_update", "destroy", "transition"}:
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
    permission_classes = [AllowAny]

    def post(self, request):
        transaction_id = request.data.get("transaction_id") or request.data.get("transactionId")
        if not transaction_id:
            return Response({"error": "transaction_id manquant"}, status=status.HTTP_400_BAD_REQUEST)

        from .services import verify_kkiapay_transaction
        try:
            kkiapay_data = verify_kkiapay_transaction(transaction_id)
        except DjangoValidationError as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        booking_id = request.data.get("booking_id")
        payment_method_code = request.data.get("payment_method", "KKIAPAY")

        if not booking_id:
            return Response({"error": "booking_id manquant"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            booking = Booking.objects.get(pk=booking_id)
        except Booking.DoesNotExist:
            return Response({"error": "Réservation introuvable"}, status=status.HTTP_404_NOT_FOUND)

        if booking.status != Booking.Status.HELD:
            return Response({"message": "Réservation déjà traitée."}, status=status.HTTP_200_OK)

        payment_method = PaymentMethod.objects.filter(code=payment_method_code).first()
        if not payment_method:
            payment_method, _ = PaymentMethod.objects.get_or_create(
                code="KKIAPAY", defaults={"label": "Mobile Money", "active": True}
            )

        try:
            booking, issued_tickets, _ = pay_and_issue_booking(
                booking,
                payment_method=payment_method,
                actor=None,
                external_reference=transaction_id,
            )
        except DjangoValidationError as exc:
            return Response({"error": exc.messages}, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            "status": "SUCCESS", 
            "booking": BookingSerializer(booking).data
        })


class FedaPayWebhookView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        import hmac
        import hashlib
        from django.conf import settings

        webhook_secret = getattr(settings, "FEDAPAY_WEBHOOK_SECRET", "")
        sig_header = request.headers.get("X-FEDAPAY-SIGNATURE") or request.META.get("HTTP_X_FEDAPAY_SIGNATURE")

        if webhook_secret and sig_header:
            computed_sig = hmac.new(
                webhook_secret.encode("utf-8"),
                request.body,
                hashlib.sha256
            ).hexdigest()
            clean_sig = sig_header.split(",")[-1].replace("v1=", "").strip() if "," in sig_header else sig_header.strip()
            if not hmac.compare_digest(computed_sig, clean_sig):
                return Response({"error": "Signature Webhook invalide"}, status=status.HTTP_400_BAD_REQUEST)

        data = request.data
        entity = data.get("entity") or data.get("v1/transaction") or data

        transaction_id = entity.get("id") or data.get("transaction_id")
        if not transaction_id:
            return Response({"error": "transaction_id manquant"}, status=status.HTTP_400_BAD_REQUEST)

        tx_status = entity.get("status")
        if tx_status and tx_status != "approved":
            return Response({"message": f"Événement ignoré pour statut {tx_status}"}, status=status.HTTP_200_OK)

        from .services import verify_fedapay_transaction
        try:
            verify_fedapay_transaction(transaction_id)
        except DjangoValidationError as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        custom_metadata = entity.get("custom_metadata") or {}
        booking_id = custom_metadata.get("booking_id") or data.get("booking_id") or request.query_params.get("booking_id")

        if not booking_id:
            return Response({"error": "booking_id manquant dans les métadonnées"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            booking = Booking.objects.get(pk=booking_id)
        except Booking.DoesNotExist:
            return Response({"error": "Réservation introuvable"}, status=status.HTTP_404_NOT_FOUND)

        if booking.status != Booking.Status.HELD:
            return Response({"message": "Réservation déjà traitée."}, status=status.HTTP_200_OK)

        payment_method = PaymentMethod.objects.filter(code="FEDAPAY").first()
        if not payment_method:
            payment_method, _ = PaymentMethod.objects.get_or_create(
                code="FEDAPAY", defaults={"label": "FedaPay Mobile Money / Carte", "active": True, "fee_percentage": Decimal("1.80")}
            )

        try:
            booking, issued_tickets, _ = pay_and_issue_booking(
                booking,
                payment_method=payment_method,
                actor=None,
                external_reference=str(transaction_id),
            )
        except DjangoValidationError as exc:
            return Response({"error": exc.messages if hasattr(exc, "messages") else str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            "status": "SUCCESS",
            "message": "Paiement FedaPay validé et billets émis avec succès.",
            "booking_id": booking.id,
            "tickets_issued": len(issued_tickets)
        }, status=status.HTTP_200_OK)


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

    @action(detail=False, methods=["post"])
    def sell_counter(self, request):
        """
        Délivre un billet directement au guichet (paiement en agence).
        Sécurisé par select_for_update contre la surréservation.
        """
        trip_id = request.data.get("trip_id")
        seat_id = request.data.get("seat_id")
        passenger_name = request.data.get("passenger_name", "Passager Guichet")
        passenger_phone = request.data.get("passenger_phone", "")

        if not trip_id or not seat_id:
            return Response({"error": "trip_id et seat_id sont requis."}, status=status.HTTP_400_BAD_REQUEST)

        from django.db import transaction
        from .models import Trip, Seat, Ticket, Passenger, Booking, TicketStatusHistory
        from django.utils import timezone

        with transaction.atomic():
            try:
                locked_trip = Trip.objects.select_for_update().get(pk=trip_id)
            except Trip.DoesNotExist:
                return Response({"error": "Trajet introuvable."}, status=status.HTTP_400_BAD_REQUEST)

            if locked_trip.departure_at < timezone.now():
                return Response({"error": "Impossible de vendre un billet pour un trajet passé."}, status=status.HTTP_400_BAD_REQUEST)

            try:
                locked_seat = Seat.objects.select_for_update().get(pk=seat_id, trip=locked_trip)
            except Seat.DoesNotExist:
                return Response({"error": "Siège introuvable pour ce trajet."}, status=status.HTTP_400_BAD_REQUEST)

            if locked_seat.status != Seat.Status.AVAILABLE:
                return Response({"error": "Désolé, ce siège vient juste d'être réservé ou vendu. Capacité atteinte pour cette place."}, status=status.HTTP_400_BAD_REQUEST)

            # Création immédiate du ticket (Paiement Guichet)
            booking = Booking.objects.create(
                trip=locked_trip,
                customer=request.user if request.user.is_authenticated else None,
                status=Booking.Status.CONFIRMED,
                amount=locked_trip.route.base_fare, # Simplification tarif
            )
            passenger = Passenger.objects.create(
                booking=booking, full_name=passenger_name, phone=passenger_phone
            )
            ticket = Ticket.objects.create(
                booking=booking,
                passenger=passenger,
                trip=locked_trip,
                seat=locked_seat,
                passenger_name=passenger_name,
                passenger_phone=passenger_phone,
                channel=Ticket.Channel.COUNTER,
                status=Ticket.Status.ISSUED,
                amount=booking.amount,
            )
            TicketStatusHistory.objects.create(ticket=ticket, to_status=Ticket.Status.ISSUED, changed_by=request.user)
            locked_seat.status = Seat.Status.PAID
            locked_seat.save(update_fields=["status", "updated_at"])

        return Response({
            "status": "SUCCESS",
            "message": "Billet délivré avec succès au guichet.",
            "ticket_reference": ticket.reference,
            "qr_token": str(ticket.qr_token)
        })


class PublicTicketDetailView(APIView):
    """
    Vue publique non-authentifiée de consultation d'un billet via sa référence unique.
    GET /api/v1/client/tickets/public/<reference>/
    """
    permission_classes = [AllowAny]

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

