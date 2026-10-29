from datetime import timedelta
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.utils import timezone
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .models import (
    BoardingPoint,
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
    PaymentIncident,
    SegmentFare,
    SegmentFareChange,
    AgencyProfile,
    AgencySettingChange,
    PaymentReceipt,
    Tax,
    WeeklySchedule,
    RouteStop,
)
from .payments import ONLINE_PROVIDERS, payment_quote
from .services import boarding_lead_minutes, boarding_time, rental_is_available, trip_fare


def public_ticket_url(ticket):
    """Lien public du billet, ou chaîne vide tant que l'adresse du site n'est pas configurée."""
    base = (settings.PUBLIC_WEB_URL or "").rstrip("/")
    return f"{base}/t/{ticket.reference}" if base else ""


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


class BoardingPointSerializer(serializers.ModelSerializer):
    location_name = serializers.CharField(source="location.name", read_only=True)
    is_used = serializers.SerializerMethodField()

    class Meta:
        model = BoardingPoint
        fields = [
            "id",
            "location",
            "location_name",
            "name",
            "active",
            "order",
            "is_used",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "location_name", "is_used", "created_at", "updated_at"]

    def validate_name(self, value):
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("Le nom du point d'embarquement est obligatoire.")
        return value

    def get_is_used(self, obj):
        return (
            obj.bookings_as_boarding_point.exists()
            or obj.bookings_as_alighting_point.exists()
            or obj.tickets_as_boarding_point.exists()
            or obj.tickets_as_alighting_point.exists()
        )


def _active_boarding_points_payload(location):
    if not location:
        return []
    return [
        {"id": pt.id, "name": pt.name, "order": pt.order, "active": pt.active}
        for pt in location.boarding_points.filter(active=True).order_by("order", "name", "id")
    ]


class LocationSerializer(serializers.ModelSerializer):
    boarding_points = serializers.SerializerMethodField()

    class Meta:
        model = Location
        fields = ["id", "name", "address", "active", "boarding_points", "created_at", "updated_at"]
        read_only_fields = ["created_at", "updated_at"]

    def get_boarding_points(self, obj):
        return _active_boarding_points_payload(obj)


class RouteStopSerializer(serializers.ModelSerializer):
    location_id = serializers.IntegerField(source="location.id", read_only=True)
    name = serializers.CharField(source="location.name", read_only=True)

    class Meta:
        model = RouteStop
        fields = ["id", "position", "location_id", "name", "offset_minutes"]


class RouteSerializer(serializers.ModelSerializer):
    origin_detail = LocationSerializer(source="origin", read_only=True)
    destination_detail = LocationSerializer(source="destination", read_only=True)
    label = serializers.CharField(source="__str__", read_only=True)
    stops = serializers.SerializerMethodField()

    class Meta:
        model = Route
        fields = [
            "id",
            "origin",
            "destination",
            "origin_detail",
            "destination_detail",
            "label",
            "stops",
            "active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def get_stops(self, obj):
        seq = obj.get_stops_sequence()
        return [
            {
                "id": loc.id,
                "name": loc.name,
                "position": idx + 1,
                "boarding_points": _active_boarding_points_payload(loc),
            }
            for idx, loc in enumerate(seq)
        ]

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


def serialized_boarding_at(serializer, trip):
    """Heure d'embarquement d'un trajet ; le réglage n'est lu qu'une fois par réponse."""
    cache = serializer.context if isinstance(serializer.context, dict) else {}
    if "_boarding_lead_minutes" not in cache:
        cache["_boarding_lead_minutes"] = boarding_lead_minutes()
    return boarding_time(trip, cache["_boarding_lead_minutes"])


class TripSerializer(serializers.ModelSerializer):
    route_detail = RouteSerializer(source="route", read_only=True)
    vehicle_detail = PublicVehicleSerializer(source="vehicle", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    available_seats = serializers.SerializerMethodField()
    current_fare = serializers.SerializerMethodField()
    boarding_at = serializers.SerializerMethodField()

    class Meta:
        model = Trip
        fields = [
            "id",
            "route",
            "route_detail",
            "vehicle",
            "vehicle_detail",
            "departure_at",
            "boarding_at",
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

    def get_boarding_at(self, obj):
        boarding = serialized_boarding_at(self, obj)
        return serializers.DateTimeField().to_representation(boarding) if boarding else None

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Si arrival_at n'est pas renseigné explicitement, on calcule via RouteStop.offset_minutes
        if not data.get("arrival_at") and instance.route_id and instance.departure_at:
            request = self.context.get("request") if isinstance(self.context, dict) else None
            dest_param = request.query_params.get("destination") if request and hasattr(request, "query_params") else None
            target_stop = None
            if dest_param:
                from .services import resolve_location
                try:
                    dest_loc = resolve_location(dest_param)
                    if dest_loc:
                        target_stop = instance.route.stops.filter(location_id=dest_loc.pk).first()
                except Exception:
                    target_stop = None
            if not target_stop:
                target_stop = instance.route.stops.order_by("-position").first()
            if target_stop and target_stop.offset_minutes is not None:
                effective_arrival = instance.departure_at + timedelta(minutes=target_stop.offset_minutes)
                data["arrival_at"] = serializers.DateTimeField().to_representation(effective_arrival)
        return data

    def get_current_fare(self, obj):
        request = self.context.get("request")
        if request and hasattr(request, "query_params"):
            origin_param = request.query_params.get("origin")
            dest_param = request.query_params.get("destination")
            if origin_param and dest_param:
                from .services import resolve_location, resolve_segment_fare
                try:
                    origin_loc = resolve_location(origin_param)
                    dest_loc = resolve_location(dest_param)
                    if origin_loc and dest_loc and origin_loc.pk != dest_loc.pk:
                        fare = resolve_segment_fare(origin_loc, dest_loc)
                        return {"id": fare.id, "name": fare.label, "amount": fare.amount, "currency": fare.currency}
                except Exception:
                    pass
        try:
            fare = trip_fare(obj)
        except ImproperlyConfigured:
            return None
        return {"id": fare.id, "name": fare.name, "amount": fare.amount, "currency": fare.currency}

    def validate(self, attrs):
        instance = self.instance or Trip()
        for key, value in attrs.items():
            setattr(instance, key, value)
        departure_at = attrs.get("departure_at") or getattr(instance, "departure_at", None)
        arrival_at = attrs.get("arrival_at") or getattr(instance, "arrival_at", None)
        if departure_at and arrival_at and arrival_at <= departure_at:
            raise serializers.ValidationError({"arrival_at": "L'arrivée doit être postérieure au départ."})
        if departure_at and arrival_at:
            dep_date = timezone.localtime(departure_at).date()
            arr_date = timezone.localtime(arrival_at).date()
            if dep_date != arr_date:
                raise serializers.ValidationError({"arrival_at": "Axis n'opère que des trajets de jour, sans trajet de nuit (même jour requis)."})
        instance.full_clean(exclude=[field for field in ("route", "vehicle") if not getattr(instance, f"{field}_id")])
        return attrs


class WeeklyScheduleSerializer(serializers.ModelSerializer):
    day_of_week_display = serializers.CharField(source="get_day_of_week_display", read_only=True)
    route_detail = RouteSerializer(source="route", read_only=True)
    vehicle_detail = PublicVehicleSerializer(source="vehicle", read_only=True)
    departure_time_display = serializers.SerializerMethodField()

    class Meta:
        model = WeeklySchedule
        fields = [
            "id",
            "day_of_week",
            "day_of_week_display",
            "route",
            "route_detail",
            "vehicle",
            "vehicle_detail",
            "departure_time",
            "departure_time_display",
            "is_active",
            "notes",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def get_departure_time_display(self, obj):
        return f"{obj.departure_time:%H:%M}" if obj.departure_time else None

    def validate(self, attrs):
        is_active = attrs.get("is_active", getattr(self.instance, "is_active", True))
        route = attrs.get("route", getattr(self.instance, "route", None))
        departure_time = attrs.get("departure_time", getattr(self.instance, "departure_time", None))
        if is_active and not route:
            raise serializers.ValidationError({"route": "Un trajet actif doit être associé à un parcours."})
        if is_active and not departure_time:
            raise serializers.ValidationError({"departure_time": "Un trajet actif doit avoir une heure de départ."})
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


def public_agency_info():
    """Informations de l'agence imprimées sur le billet (vides = « À renseigner »). Jamais les comptes bancaires."""
    profile = AgencyProfile.objects.filter(pk=1).first()
    return {field: (getattr(profile, field, "") or "").strip() for field in AgencyProfile.PUBLIC_FIELDS}


def _display_name(user):
    return (user.get_full_name() or user.username) if user else ""


# Valeurs du champ « mode » de FedaPay réellement observées, et leur libellé imprimé. Seule « momo_test »
# a été vue (sandbox). Toute autre valeur, ou son absence, s'imprime « Paiement en ligne » : rien n'est deviné.
# Ajouter ici chaque valeur réelle une fois constatée sur une transaction live.
FEDAPAY_MODE_LABELS = {"momo_test": "Mobile Money (test)"}


def online_payment_label(mode):
    return FEDAPAY_MODE_LABELS.get((mode or "").strip().lower(), "Paiement en ligne")


def ticket_print_info(ticket):
    """
    Données imprimées sur le billet, toutes lues sur le serveur ; les apps et le site ne calculent rien.
    Chaîne vide = information absente (l'affichage écrit « À renseigner » ou masque la ligne, selon le cas).
    """
    paid = ticket.status in {Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CHECKED, Ticket.Status.COMPLETED}
    booking = ticket.booking
    receipts = PaymentReceipt.objects.filter(refund_due=False)
    receipt = (
        receipts.filter(booking=booking).first() if booking else None
    ) or receipts.filter(ticket=ticket).first()
    seller = booking.sold_by if booking and booking.sold_by_id else None
    if seller is None and receipt and receipt.source == PaymentReceipt.Source.COUNTER:
        seller = receipt.recorded_by
    if seller is not None:
        sale = f"Vendeur : {_display_name(seller)}"
    elif ticket.channel == Ticket.Channel.ONLINE:
        sale = "Vente en ligne"
    else:
        sale = "Vente au guichet"
    payment_mode = ""
    if paid and receipt:
        if receipt.provider.upper() in ONLINE_PROVIDERS:
            payment_mode = online_payment_label(receipt.provider_mode)
        else:
            # Au guichet : le nom du moyen tel que configuré par l'administrateur (ex. « Espèces »).
            method = PaymentMethod.objects.filter(code__iexact=receipt.provider).first()
            payment_mode = method.label if method else ""
    agency = public_agency_info()
    origin = ticket.boarding_location
    destination = ticket.alighting_location
    dep_time, dep_label, is_offset = ticket.get_departure_time_and_label()
    # Décomposition HT / taxes : seulement si l'IFU de l'agence est renseigné et si le billet a ses taxes figées.
    show_taxes = bool(agency["ifu"]) and ticket.price_excl_tax is not None
    return {
        "title": "Billet de transport",
        "paid": paid,
        "sale": sale,
        "payment_mode": payment_mode,
        "buyer_ifu": booking.buyer_ifu if booking else "",
        "boarding_place": (origin.address or "").strip() if origin else "",
        "origin": origin.name if origin else "",
        "destination": destination.name if destination else "",
        "boarding_point_name": (ticket.boarding_point_name or "").strip(),
        "alighting_point_name": (ticket.alighting_point_name or "").strip(),
        "boarding_display": ticket.boarding_display,
        "alighting_display": ticket.alighting_display,
        "segment_label": ticket.segment_label,
        "departure_label": dep_label,
        "departure_at": dep_time.isoformat() if dep_time else (ticket.trip.departure_at.isoformat() if ticket.trip else None),
        "is_offset": is_offset,
        "price_incl_tax": int(ticket.amount),
        "price_excl_tax": int(ticket.price_excl_tax) if show_taxes else None,
        "tax_lines": ticket.tax_lines if show_taxes else [],
        "agency": agency,
        "conditions": "",
    }


class TicketSerializer(serializers.ModelSerializer):
    trip_detail = TripSerializer(source="trip", read_only=True)
    seat_detail = SeatSerializer(source="seat", read_only=True)
    customer_detail = UserSerializer(source="customer", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    channel_display = serializers.CharField(source="get_channel_display", read_only=True)
    status_history = TicketStatusHistorySerializer(many=True, read_only=True)
    controls = TicketControlSerializer(many=True, read_only=True)
    public_url = serializers.SerializerMethodField()
    print_info = serializers.SerializerMethodField()
    origin_detail = LocationSerializer(source="boarding_location", read_only=True)
    destination_detail = LocationSerializer(source="alighting_location", read_only=True)
    origin_name = serializers.CharField(source="boarding_location.name", read_only=True)
    destination_name = serializers.CharField(source="alighting_location.name", read_only=True)
    boarding_display = serializers.CharField(read_only=True)
    alighting_display = serializers.CharField(read_only=True)
    segment_label = serializers.CharField(read_only=True)
    departure_label = serializers.SerializerMethodField()
    effective_departure_at = serializers.SerializerMethodField()
    seat_preference = serializers.BooleanField(read_only=True)
    seat_summary_label = serializers.CharField(read_only=True)

    class Meta:
        model = Ticket
        fields = [
            "id",
            "reference",
            "print_info",
            "booking",
            "public_url",
            "trip",
            "trip_detail",
            "origin",
            "destination",
            "origin_name",
            "destination_name",
            "origin_detail",
            "destination_detail",
            "boarding_point",
            "alighting_point",
            "boarding_point_name",
            "alighting_point_name",
            "boarding_display",
            "alighting_display",
            "segment_label",
            "departure_label",
            "effective_departure_at",
            "seat",
            "seat_detail",
            "seat_preference",
            "seat_summary_label",
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

    def get_public_url(self, obj):
        return public_ticket_url(obj)

    def get_print_info(self, obj):
        return ticket_print_info(obj)

    def get_departure_label(self, obj):
        _, label, _ = obj.get_departure_time_and_label()
        return label

    def get_effective_departure_at(self, obj):
        dep_time, _, _ = obj.get_departure_time_and_label()
        return dep_time.isoformat() if dep_time else None


class ControllerTicketSerializer(serializers.ModelSerializer):
    trip_detail = TripSerializer(source="trip", read_only=True)
    seat_detail = SeatSerializer(source="seat", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    origin_name = serializers.CharField(source="boarding_location.name", read_only=True)
    destination_name = serializers.CharField(source="alighting_location.name", read_only=True)
    segment_label = serializers.CharField(read_only=True)

    class Meta:
        model = Ticket
        fields = [
            "id",
            "reference",
            "trip",
            "trip_detail",
            "origin_name",
            "destination_name",
            "segment_label",
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
    origin = serializers.CharField(max_length=120, required=False, allow_blank=True)
    destination = serializers.CharField(max_length=120, required=False, allow_blank=True)
    boarding_point_id = serializers.IntegerField(required=False, allow_null=True)
    alighting_point_id = serializers.IntegerField(required=False, allow_null=True)
    boarding_point = serializers.IntegerField(required=False, allow_null=True)
    alighting_point = serializers.IntegerField(required=False, allow_null=True)


class BookingPassengerSerializer(serializers.ModelSerializer):
    passenger_type_display = serializers.CharField(source="get_passenger_type_display", read_only=True)

    class Meta:
        model = Passenger
        fields = ["id", "full_name", "phone", "passenger_type", "passenger_type_display"]


class BookingCreatePassengerSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=160)
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    passenger_type = serializers.ChoiceField(choices=Passenger.Type.choices, default=Passenger.Type.ADULT)
    seat = serializers.PrimaryKeyRelatedField(
        queryset=Seat.objects.all(), required=False, allow_null=True, default=None
    )


class BookingCreateSerializer(serializers.Serializer):
    trip = serializers.PrimaryKeyRelatedField(queryset=Trip.objects.all())
    origin = serializers.CharField(max_length=120, required=False, allow_blank=True)
    destination = serializers.CharField(max_length=120, required=False, allow_blank=True)
    boarding_point_id = serializers.IntegerField(required=False, allow_null=True)
    alighting_point_id = serializers.IntegerField(required=False, allow_null=True)
    boarding_point = serializers.IntegerField(required=False, allow_null=True)
    alighting_point = serializers.IntegerField(required=False, allow_null=True)
    contact_phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    contact_email = serializers.EmailField(required=False, allow_blank=True)
    buyer_ifu = serializers.CharField(max_length=30, required=False, allow_blank=True)
    passengers = BookingCreatePassengerSerializer(many=True, allow_empty=False, min_length=1, max_length=8)

    def validate(self, attrs):
        trip = attrs["trip"]
        passengers = attrs["passengers"]
        chosen_seats = [passenger["seat"] for passenger in passengers if passenger.get("seat") is not None]
        seat_ids = [seat.pk for seat in chosen_seats]
        if len(seat_ids) != len(set(seat_ids)):
            raise serializers.ValidationError({"passengers": "Chaque passager doit avoir un siège différent."})
        if any(seat.trip_id != trip.pk for seat in chosen_seats):
            raise serializers.ValidationError({"passengers": "Tous les sièges doivent appartenir au trajet."})
        return attrs


class BookingSerializer(serializers.ModelSerializer):
    trip_detail = TripSerializer(source="trip", read_only=True)
    customer_detail = UserSerializer(source="customer", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    client_status_display = serializers.CharField(read_only=True)
    passengers = BookingPassengerSerializer(many=True, read_only=True)
    tickets = TicketSerializer(many=True, read_only=True)
    payment_quotes = serializers.SerializerMethodField()
    origin_detail = LocationSerializer(source="boarding_location", read_only=True)
    destination_detail = LocationSerializer(source="alighting_location", read_only=True)
    origin_name = serializers.CharField(source="boarding_location.name", read_only=True)
    destination_name = serializers.CharField(source="alighting_location.name", read_only=True)
    boarding_display = serializers.CharField(read_only=True)
    alighting_display = serializers.CharField(read_only=True)
    segment_label = serializers.CharField(read_only=True)
    departure_label = serializers.SerializerMethodField()
    effective_departure_at = serializers.SerializerMethodField()

    class Meta:
        model = Booking
        fields = [
            "id",
            "reference",
            "trip",
            "trip_detail",
            "origin",
            "destination",
            "origin_name",
            "destination_name",
            "origin_detail",
            "destination_detail",
            "boarding_point",
            "alighting_point",
            "boarding_point_name",
            "alighting_point_name",
            "boarding_display",
            "alighting_display",
            "segment_label",
            "departure_label",
            "effective_departure_at",
            "customer",
            "customer_detail",
            "contact_phone",
            "contact_email",
            "buyer_ifu",
            "status",
            "status_display",
            "client_status_display",
            "reservation_expires_at",
            "amount",
            "currency",
            "passengers",
            "tickets",
            "payment_quotes",
            "created_at",
        ]

    def get_departure_label(self, obj):
        _, label, _ = obj.get_departure_time_and_label()
        return label

    def get_effective_departure_at(self, obj):
        dep_time, _, _ = obj.get_departure_time_and_label()
        return dep_time.isoformat() if dep_time else None

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
        # Nouvelle demande : le début ne peut pas être déjà passé.
        if self.instance is None and attrs.get("starts_at") and attrs["starts_at"] <= timezone.now():
            raise serializers.ValidationError({"starts_at": "Le début de la location doit être dans le futur."})
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
    boarding_point_name = serializers.CharField(read_only=True)
    alighting_point_name = serializers.CharField(read_only=True)
    boarding_display = serializers.CharField(read_only=True)
    alighting_display = serializers.CharField(read_only=True)
    departure_at = serializers.SerializerMethodField()
    departure_label = serializers.SerializerMethodField()
    segment_label = serializers.CharField(read_only=True)
    boarding_at = serializers.SerializerMethodField()
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    formatted_amount = serializers.SerializerMethodField()
    company_name = serializers.SerializerMethodField()
    public_url = serializers.SerializerMethodField()
    print_info = serializers.SerializerMethodField()
    arrival_at = serializers.SerializerMethodField()

    class Meta:
        model = Ticket
        fields = [
            "reference",
            "print_info",
            "arrival_at",
            "status",
            "status_display",
            "passenger_name",
            "seat_label",
            "origin",
            "destination",
            "boarding_point_name",
            "alighting_point_name",
            "boarding_display",
            "alighting_display",
            "segment_label",
            "departure_label",
            "departure_at",
            "boarding_at",
            "amount",
            "currency",
            "formatted_amount",
            "qr_token",
            "company_name",
            "public_url",
            "created_at",
        ]
        read_only_fields = fields

    def get_print_info(self, obj):
        return ticket_print_info(obj)

    def get_arrival_at(self, obj):
        return serializers.DateTimeField().to_representation(obj.trip.arrival_at) if obj.trip.arrival_at else None

    def get_seat_label(self, obj):
        return obj.seat.number if obj.seat else "N/A"

    def get_origin(self, obj):
        loc = obj.boarding_location
        return loc.name if loc else ""

    def get_destination(self, obj):
        loc = obj.alighting_location
        return loc.name if loc else ""

    def get_departure_at(self, obj):
        dep_time, _, _ = obj.get_departure_time_and_label()
        return dep_time.isoformat() if dep_time else (obj.trip.departure_at.isoformat() if obj.trip else None)

    def get_departure_label(self, obj):
        _, label, _ = obj.get_departure_time_and_label()
        return label

    def get_boarding_at(self, obj):
        boarding = serialized_boarding_at(self, obj.trip) if obj.trip else None
        return boarding.isoformat() if boarding else None

    def get_formatted_amount(self, obj):
        return f"{obj.amount:,.0f} {obj.currency or 'FCFA'}".replace(",", " ")

    def get_company_name(self, obj):
        return "AXIS Transport"

    def get_public_url(self, obj):
        return public_ticket_url(obj)


class PaymentIncidentSerializer(serializers.ModelSerializer):
    """Incident de paiement, en lecture seule sauf la case « traité » et sa note."""

    source_display = serializers.CharField(source="get_source_display", read_only=True)
    booking_reference = serializers.CharField(source="booking.reference", read_only=True, default="")

    class Meta:
        model = PaymentIncident
        fields = [
            "id", "created_at", "source", "source_display", "provider", "event", "external_id",
            "amount", "currency", "amount_verified", "booking", "booking_reference", "reason",
            "handled", "handled_note",
        ]
        read_only_fields = [field for field in fields if field not in ("handled", "handled_note")]


class SegmentFareSerializer(serializers.ModelSerializer):
    """Prix d'un tronçon de la ligne, pour l'administrateur. Seul le prix se modifie."""

    start_name = serializers.CharField(source="start.location.name", read_only=True)
    end_name = serializers.CharField(source="end.location.name", read_only=True)
    start_position = serializers.IntegerField(source="start.position", read_only=True)
    end_position = serializers.IntegerField(source="end.position", read_only=True)
    label = serializers.CharField(read_only=True)
    updated_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SegmentFare
        fields = [
            "id", "start_name", "end_name", "start_position", "end_position", "label",
            "amount", "currency", "updated_at", "updated_by_name",
        ]
        read_only_fields = [field for field in fields if field != "amount"]

    def get_updated_by_name(self, obj):
        user = obj.updated_by
        return (user.get_full_name() or user.username) if user else ""


class ManualTicketChangeSerializer(serializers.ModelSerializer):
    """Journal des statuts de billet forcés à la main, en lecture seule."""

    reference = serializers.CharField(source="ticket.reference", read_only=True)
    from_status_display = serializers.SerializerMethodField()
    to_status_display = serializers.CharField(source="get_to_status_display", read_only=True)
    changed_by_name = serializers.SerializerMethodField()

    class Meta:
        model = TicketStatusHistory
        fields = [
            "id", "changed_at", "reference", "from_status", "from_status_display", "to_status", "to_status_display",
            "changed_by_name", "note",
        ]
        read_only_fields = fields

    def get_from_status_display(self, obj):
        return dict(Ticket.Status.choices).get(obj.from_status, obj.from_status)

    def get_changed_by_name(self, obj):
        user = obj.changed_by
        if user is None:
            return "—"
        return user.get_full_name() or user.username


class SegmentFareChangeSerializer(serializers.ModelSerializer):
    """Journal des prix de tronçon, en lecture seule."""

    label = serializers.CharField(source="fare.label", read_only=True)
    changed_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SegmentFareChange
        fields = ["id", "created_at", "label", "old_amount", "new_amount", "changed_by_name"]
        read_only_fields = fields

    def get_changed_by_name(self, obj):
        user = obj.changed_by
        if user is None:
            return "Chargement initial"
        return user.get_full_name() or user.username


class AgencyProfileSerializer(serializers.ModelSerializer):
    """Fiche de l'agence pour la page admin (comptes bancaires compris, jamais imprimés)."""

    updated_by_name = serializers.SerializerMethodField()

    class Meta:
        model = AgencyProfile
        fields = AgencyProfile.EDITABLE_FIELDS + ["updated_at", "updated_by_name"]
        read_only_fields = ["updated_at", "updated_by_name"]

    def validate(self, attrs):
        return {key: value.strip() for key, value in attrs.items()}

    def get_updated_by_name(self, obj):
        return _display_name(obj.updated_by)


class TaxSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tax
        fields = ["id", "name", "rate", "active", "included", "updated_at"]
        read_only_fields = ["id", "updated_at"]

    def validate_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Le nom de la taxe est obligatoire.")
        return value

    def validate_rate(self, value):
        if value < 0 or value >= 100:
            raise serializers.ValidationError("Le taux doit être compris entre 0 et 100 (exclu).")
        return value


class AgencySettingChangeSerializer(serializers.ModelSerializer):
    changed_by_name = serializers.SerializerMethodField()
    kind_display = serializers.CharField(source="get_kind_display", read_only=True)

    class Meta:
        model = AgencySettingChange
        fields = ["id", "changed_at", "kind", "kind_display", "label", "old_value", "new_value", "changed_by_name"]
        read_only_fields = fields

    def get_changed_by_name(self, obj):
        return _display_name(obj.changed_by) or "—"
