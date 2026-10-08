from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .models import (
    Booking,
    FareRule,
    FeatureFlag,
    Location,
    Parcel,
    ParcelStatusHistory,
    PaymentMethod,
    Passenger,
    RentalBooking,
    Route,
    Seat,
    SystemSetting,
    Ticket,
    TicketControl,
    TicketStatusHistory,
    Transaction,
    Trip,
    User,
    Vehicle,
)
from .payments import ONLINE_PROVIDERS, payment_quote
from .services import rental_is_available, resolve_fare


class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False)
    role_display = serializers.CharField(source="get_role_display", read_only=True)

    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name", "phone", "role", "role_display", "password"]

    def validate_password(self, value):
        validate_password(value)
        return value

    def create(self, validated_data):
        password = validated_data.pop("password", None)
        user = User(**validated_data)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.full_clean()
        user.save()
        return user

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        instance = super().update(instance, validated_data)
        if password:
            instance.set_password(password)
            instance.save(update_fields=["password"])
        return instance


class LocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Location
        fields = "__all__"
        read_only_fields = ["created_at", "updated_at"]


class RouteSerializer(serializers.ModelSerializer):
    origin_detail = LocationSerializer(source="origin", read_only=True)
    destination_detail = LocationSerializer(source="destination", read_only=True)
    label = serializers.CharField(source="__str__", read_only=True)

    class Meta:
        model = Route
        fields = ["id", "origin", "destination", "origin_detail", "destination_detail", "label", "active", "created_at", "updated_at"]
        read_only_fields = ["created_at", "updated_at"]

    def validate(self, attrs):
        if attrs.get("origin", getattr(self.instance, "origin", None)) == attrs.get(
            "destination", getattr(self.instance, "destination", None)
        ):
            raise serializers.ValidationError("L'origine et la destination doivent être différentes.")
        return attrs


class VehicleSerializer(serializers.ModelSerializer):
    category_display = serializers.CharField(source="get_category_display", read_only=True)
    state_display = serializers.CharField(source="get_state_display", read_only=True)
    base_location_detail = LocationSerializer(source="base_location", read_only=True)

    class Meta:
        model = Vehicle
        fields = "__all__"
        read_only_fields = ["created_at", "updated_at"]

    def validate(self, attrs):
        instance = self.instance or Vehicle()
        for key, value in attrs.items():
            setattr(instance, key, value)
        instance.full_clean(exclude=["registration_number"] if not instance.registration_number else None)
        return attrs


class PublicVehicleSerializer(serializers.ModelSerializer):
    category_display = serializers.CharField(source="get_category_display", read_only=True)
    state_display = serializers.CharField(source="get_state_display", read_only=True)
    base_location_detail = LocationSerializer(source="base_location", read_only=True)

    class Meta:
        model = Vehicle
        fields = [
            "id",
            "category",
            "category_display",
            "name",
            "capacity",
            "state",
            "state_display",
            "base_location",
            "base_location_detail",
            "description",
            "rental_daily_rate",
            "driver_available",
        ]


class FareRuleSerializer(serializers.ModelSerializer):
    route_detail = RouteSerializer(source="route", read_only=True)
    rule_type_display = serializers.CharField(source="get_rule_type_display", read_only=True)

    class Meta:
        model = FareRule
        fields = "__all__"
        read_only_fields = ["created_at", "updated_at"]

    def validate(self, attrs):
        instance = self.instance or FareRule()
        for key, value in attrs.items():
            setattr(instance, key, value)
        instance.full_clean(exclude=["route"] if not instance.route_id else None)
        return attrs


class SeatSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source="get_status_display", read_only=True)

    class Meta:
        model = Seat
        fields = [
            "id",
            "trip",
            "number",
            "row",
            "column",
            "allowed_passenger_types",
            "status",
            "status_display",
            "hold_expires_at",
        ]


class TripSerializer(serializers.ModelSerializer):
    route_detail = RouteSerializer(source="route", read_only=True)
    vehicle_detail = PublicVehicleSerializer(source="vehicle", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    available_seats = serializers.SerializerMethodField()
    current_fare = serializers.SerializerMethodField()

    class Meta:
        model = Trip
        fields = [
            "id",
            "route",
            "route_detail",
            "vehicle",
            "vehicle_detail",
            "departure_at",
            "arrival_at",
            "status",
            "status_display",
            "note",
            "available_seats",
            "current_fare",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def get_available_seats(self, obj):
        return obj.seats.filter(status=Seat.Status.AVAILABLE).count()

    def get_current_fare(self, obj):
        try:
            fare = resolve_fare(obj)
        except ImproperlyConfigured:
            return None
        return {"id": fare.id, "name": fare.name, "amount": fare.amount, "currency": fare.currency}

    def validate(self, attrs):
        instance = self.instance or Trip()
        for key, value in attrs.items():
            setattr(instance, key, value)
        instance.full_clean(exclude=[field for field in ("route", "vehicle") if not getattr(instance, f"{field}_id")])
        return attrs


class FeatureFlagSerializer(serializers.ModelSerializer):
    label = serializers.CharField(source="get_key_display", read_only=True)

    class Meta:
        model = FeatureFlag
        fields = ["id", "key", "label", "enabled", "configuration", "created_at", "updated_at"]
        read_only_fields = ["created_at", "updated_at"]


class PublicFeatureFlagSerializer(serializers.ModelSerializer):
    label = serializers.CharField(source="get_key_display", read_only=True)

    class Meta:
        model = FeatureFlag
        fields = ["id", "key", "label", "enabled"]


class SystemSettingSerializer(serializers.ModelSerializer):
    class Meta:
        model = SystemSetting
        fields = "__all__"
        read_only_fields = ["created_at", "updated_at"]


class TicketStatusHistorySerializer(serializers.ModelSerializer):
    changed_by_name = serializers.CharField(source="changed_by.get_full_name", read_only=True)
    to_status_display = serializers.CharField(source="get_to_status_display", read_only=True)

    class Meta:
        model = TicketStatusHistory
        fields = ["id", "from_status", "to_status", "to_status_display", "changed_by", "changed_by_name", "changed_at", "note"]


class TicketControlSerializer(serializers.ModelSerializer):
    controller_name = serializers.CharField(source="controller.get_full_name", read_only=True)
    result_display = serializers.CharField(source="get_result_display", read_only=True)

    class Meta:
        model = TicketControl
        fields = ["id", "ticket", "controller", "controller_name", "controlled_at", "method", "result", "result_display", "note"]


class TicketSerializer(serializers.ModelSerializer):
    trip_detail = TripSerializer(source="trip", read_only=True)
    seat_detail = SeatSerializer(source="seat", read_only=True)
    customer_detail = UserSerializer(source="customer", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    channel_display = serializers.CharField(source="get_channel_display", read_only=True)
    status_history = TicketStatusHistorySerializer(many=True, read_only=True)
    controls = TicketControlSerializer(many=True, read_only=True)

    class Meta:
        model = Ticket
        fields = [
            "id",
            "reference",
            "trip",
            "trip_detail",
            "seat",
            "seat_detail",
            "customer",
            "customer_detail",
            "passenger_name",
            "passenger_phone",
            "status",
            "status_display",
            "qr_token",
            "channel",
            "channel_display",
            "reservation_expires_at",
            "amount",
            "currency",
            "status_history",
            "controls",
            "created_at",
        ]


class ControllerTicketSerializer(serializers.ModelSerializer):
    trip_detail = TripSerializer(source="trip", read_only=True)
    seat_detail = SeatSerializer(source="seat", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)

    class Meta:
        model = Ticket
        fields = [
            "id",
            "reference",
            "trip",
            "trip_detail",
            "seat",
            "seat_detail",
            "passenger_name",
            "passenger_phone",
            "status",
            "status_display",
            "qr_token",
        ]
        read_only_fields = fields


class TicketCreateSerializer(serializers.Serializer):
    trip = serializers.PrimaryKeyRelatedField(queryset=Trip.objects.all())
    seat = serializers.PrimaryKeyRelatedField(queryset=Seat.objects.all())
    passenger_name = serializers.CharField(max_length=160)
    passenger_phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    channel = serializers.ChoiceField(choices=Ticket.Channel.choices, required=False)


class BookingPassengerSerializer(serializers.ModelSerializer):
    passenger_type_display = serializers.CharField(source="get_passenger_type_display", read_only=True)

    class Meta:
        model = Passenger
        fields = ["id", "full_name", "phone", "passenger_type", "passenger_type_display"]


class BookingCreatePassengerSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=160)
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    passenger_type = serializers.ChoiceField(choices=Passenger.Type.choices, default=Passenger.Type.ADULT)
    seat = serializers.PrimaryKeyRelatedField(queryset=Seat.objects.all())


class BookingCreateSerializer(serializers.Serializer):
    trip = serializers.PrimaryKeyRelatedField(queryset=Trip.objects.all())
    contact_phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    contact_email = serializers.EmailField(required=False, allow_blank=True)
    passengers = BookingCreatePassengerSerializer(many=True, allow_empty=False, min_length=1, max_length=8)

    def validate(self, attrs):
        trip = attrs["trip"]
        passengers = attrs["passengers"]
        seat_ids = [passenger["seat"].pk for passenger in passengers]
        if len(seat_ids) != len(set(seat_ids)):
            raise serializers.ValidationError({"passengers": "Chaque passager doit avoir un siège différent."})
        if any(passenger["seat"].trip_id != trip.pk for passenger in passengers):
            raise serializers.ValidationError({"passengers": "Tous les sièges doivent appartenir au trajet."})
        return attrs


class BookingSerializer(serializers.ModelSerializer):
    trip_detail = TripSerializer(source="trip", read_only=True)
    customer_detail = UserSerializer(source="customer", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    passengers = BookingPassengerSerializer(many=True, read_only=True)
    tickets = TicketSerializer(many=True, read_only=True)
    payment_quotes = serializers.SerializerMethodField()

    class Meta:
        model = Booking
        fields = [
            "id",
            "reference",
            "trip",
            "trip_detail",
            "customer",
            "customer_detail",
            "contact_phone",
            "contact_email",
            "status",
            "status_display",
            "reservation_expires_at",
            "amount",
            "currency",
            "passengers",
            "tickets",
            "payment_quotes",
            "created_at",
        ]

    def get_payment_quotes(self, obj):
        """Montant à payer par moyen de paiement (frais inclus), calculé par le serveur."""
        if obj.status != Booking.Status.HELD:
            return []
        if not hasattr(self, "_active_payment_methods"):
            self._active_payment_methods = list(PaymentMethod.objects.filter(active=True))
        return [payment_quote(obj, method) for method in self._active_payment_methods]


class ParcelStatusHistorySerializer(serializers.ModelSerializer):
    changed_by_name = serializers.CharField(source="changed_by.get_full_name", read_only=True)
    to_status_display = serializers.CharField(source="get_to_status_display", read_only=True)

    class Meta:
        model = ParcelStatusHistory
        fields = ["id", "from_status", "to_status", "to_status_display", "changed_by", "changed_by_name", "changed_at", "note"]


class ParcelSerializer(serializers.ModelSerializer):
    origin_detail = LocationSerializer(source="origin", read_only=True)
    destination_detail = LocationSerializer(source="destination", read_only=True)
    trip_detail = TripSerializer(source="trip", read_only=True)
    customer_detail = UserSerializer(source="customer", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    status_history = ParcelStatusHistorySerializer(many=True, read_only=True)

    class Meta:
        model = Parcel
        fields = "__all__"
        read_only_fields = [
            "tracking_number",
            "customer",
            "status",
            "amount",
            "currency",
            "created_at",
            "updated_at",
        ]

    def validate(self, attrs):
        instance = self.instance or Parcel()
        for key, value in attrs.items():
            setattr(instance, key, value)
        excluded = [name for name in ("origin", "destination") if not getattr(instance, f"{name}_id")]
        instance.full_clean(exclude=excluded)
        return attrs


class RentalBookingSerializer(serializers.ModelSerializer):
    vehicle_detail = PublicVehicleSerializer(source="vehicle", read_only=True)
    customer_detail = UserSerializer(source="customer", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)

    class Meta:
        model = RentalBooking
        fields = "__all__"
        read_only_fields = [
            "reference",
            "customer",
            "status",
            "deposit_amount",
            "total_amount",
            "currency",
            "created_at",
            "updated_at",
        ]

    def validate(self, attrs):
        instance = self.instance or RentalBooking()
        for key, value in attrs.items():
            setattr(instance, key, value)
        instance.full_clean(exclude=["customer"] if not instance.customer_id else None)
        if instance.vehicle_id and instance.starts_at and instance.ends_at and not rental_is_available(
            instance.vehicle, instance.starts_at, instance.ends_at, exclude_booking=self.instance
        ):
            raise serializers.ValidationError("Ce véhicule n'est pas disponible sur la période choisie.")
        return attrs


class PaymentMethodSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentMethod
        fields = "__all__"
        read_only_fields = ["created_at", "updated_at"]


class PublicPaymentMethodSerializer(serializers.ModelSerializer):
    # Vrai si le moyen se paie en ligne ; faux s'il n'est encaissable qu'au guichet.
    online = serializers.SerializerMethodField()

    class Meta:
        model = PaymentMethod
        fields = ["id", "code", "label", "fee_percentage", "active", "online"]

    def get_online(self, obj):
        return obj.code.upper() in ONLINE_PROVIDERS


class TransactionSerializer(serializers.ModelSerializer):
    payment_method_detail = PaymentMethodSerializer(source="payment_method", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)

    class Meta:
        model = Transaction
        fields = "__all__"
        read_only_fields = ["reference", "created_at", "updated_at"]


class PublicTicketDetailSerializer(serializers.ModelSerializer):
    passenger_name = serializers.CharField(read_only=True)
    seat_label = serializers.SerializerMethodField()
    origin = serializers.SerializerMethodField()
    destination = serializers.SerializerMethodField()
    departure_at = serializers.SerializerMethodField()
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    formatted_amount = serializers.SerializerMethodField()
    company_name = serializers.SerializerMethodField()
    public_url = serializers.SerializerMethodField()

    class Meta:
        model = Ticket
        fields = [
            "reference",
            "status",
            "status_display",
            "passenger_name",
            "seat_label",
            "origin",
            "destination",
            "departure_at",
            "amount",
            "currency",
            "formatted_amount",
            "qr_token",
            "company_name",
            "public_url",
            "created_at",
        ]
        read_only_fields = fields

    def get_seat_label(self, obj):
        return obj.seat.number if obj.seat else "N/A"

    def get_origin(self, obj):
        return obj.trip.route.origin.name if obj.trip and obj.trip.route and obj.trip.route.origin else ""

    def get_destination(self, obj):
        return obj.trip.route.destination.name if obj.trip and obj.trip.route and obj.trip.route.destination else ""

    def get_departure_at(self, obj):
        return obj.trip.departure_at.isoformat() if obj.trip and obj.trip.departure_at else None

    def get_formatted_amount(self, obj):
        return f"{obj.amount:,.0f} {obj.currency or 'FCFA'}".replace(",", " ")

    def get_company_name(self, obj):
        return "AXIS Transport"

    def get_public_url(self, obj):
        domain = getattr(settings, "PUBLIC_WEB_URL", "https://axis.bj")
        return f"{domain}/t/{obj.reference}"

