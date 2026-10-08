import uuid
from decimal import Decimal

from django.contrib.auth.models import AbstractUser
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models import Q
from django.utils import timezone


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class User(AbstractUser):
    class Role(models.TextChoices):
        CLIENT = "CLIENT", "Client"
        COUNTER = "COUNTER", "Guichetier"
        CONTROLLER = "CONTROLLER", "Contrôleur"
        ADMIN = "ADMIN", "Administrateur"

    role = models.CharField(max_length=20, choices=Role.choices, default=Role.CLIENT, db_index=True)
    phone = models.CharField(max_length=32, blank=True)

    @property
    def is_axis_staff(self):
        return self.role in {self.Role.COUNTER, self.Role.CONTROLLER, self.Role.ADMIN}


class Location(TimeStampedModel):
    name = models.CharField(max_length=120, unique=True)
    address = models.CharField(max_length=255, blank=True)
    active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Route(TimeStampedModel):
    origin = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="routes_from")
    destination = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="routes_to")
    active = models.BooleanField(default=True)

    class Meta:
        ordering = ["origin__name", "destination__name"]
        constraints = [
            models.UniqueConstraint(fields=["origin", "destination"], name="unique_axis_route"),
            models.CheckConstraint(condition=~Q(origin=models.F("destination")), name="route_distinct_locations"),
        ]

    def __str__(self):
        return f"{self.origin} → {self.destination}"


class Vehicle(TimeStampedModel):
    class Category(models.TextChoices):
        BUS = "BUS", "Bus"
        RENTAL = "RENTAL", "Véhicule de location"

    class State(models.TextChoices):
        ACTIVE = "ACTIVE", "Actif"
        MAINTENANCE = "MAINTENANCE", "Maintenance"
        UNAVAILABLE = "UNAVAILABLE", "Indisponible"

    category = models.CharField(max_length=16, choices=Category.choices, db_index=True)
    name = models.CharField(max_length=120)
    registration_number = models.CharField(max_length=80, unique=True, null=True, blank=True)
    capacity = models.PositiveIntegerField(null=True, blank=True)
    seat_configuration = models.JSONField(
        default=list,
        blank=True,
        help_text="Liste configurable de sièges, ex. [{\"label\": \"1A\", \"row\": 1, \"column\": 1}]",
    )
    state = models.CharField(max_length=20, choices=State.choices, default=State.ACTIVE, db_index=True)
    base_location = models.ForeignKey(
        Location, on_delete=models.PROTECT, related_name="vehicles", null=True, blank=True
    )
    description = models.TextField(blank=True)
    rental_daily_rate = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    driver_available = models.BooleanField(default=False)

    class Meta:
        ordering = ["category", "name"]

    def clean(self):
        super().clean()
        labels = self.seat_labels
        if len(labels) != len(set(labels)):
            raise ValidationError({"seat_configuration": "Chaque libellé de siège doit être unique."})
        if self.capacity is not None and labels and len(labels) != self.capacity:
            raise ValidationError(
                {"seat_configuration": "Le plan de sièges doit contenir exactement le nombre de places configuré."}
            )
        allowed_types = {"ADULT", "CHILD"}
        for item in self.seat_configuration or []:
            if not isinstance(item, dict):
                continue
            configured_types = item.get("allowed_passenger_types", [])
            if not isinstance(configured_types, list) or not set(configured_types).issubset(allowed_types):
                raise ValidationError(
                    {
                        "seat_configuration": (
                            "allowed_passenger_types doit être une liste composée de ADULT et/ou CHILD."
                        )
                    }
                )

    @property
    def seat_labels(self):
        labels = []
        for item in self.seat_configuration or []:
            label = item.get("label") if isinstance(item, dict) else str(item)
            if label:
                labels.append(str(label))
        if not labels and self.capacity:
            labels = [str(number) for number in range(1, self.capacity + 1)]
        return labels

    def __str__(self):
        return self.name


class Trip(TimeStampedModel):
    class Status(models.TextChoices):
        SCHEDULED = "SCHEDULED", "Planifié"
        BOARDING = "BOARDING", "Embarquement"
        IN_PROGRESS = "IN_PROGRESS", "En cours"
        COMPLETED = "COMPLETED", "Terminé"
        CANCELLED = "CANCELLED", "Annulé"

    route = models.ForeignKey(Route, on_delete=models.PROTECT, related_name="trips")
    vehicle = models.ForeignKey(Vehicle, on_delete=models.PROTECT, related_name="trips")
    departure_at = models.DateTimeField(db_index=True)
    arrival_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.SCHEDULED, db_index=True)
    note = models.TextField(blank=True)

    class Meta:
        ordering = ["departure_at"]
        indexes = [models.Index(fields=["status", "departure_at"])]

    def clean(self):
        super().clean()
        if self.vehicle_id and self.vehicle.category != Vehicle.Category.BUS:
            raise ValidationError({"vehicle": "Un trajet de ligne doit utiliser un véhicule de catégorie bus."})
        if self.arrival_at and self.arrival_at <= self.departure_at:
            raise ValidationError({"arrival_at": "L'arrivée doit être postérieure au départ."})
        if self.arrival_at:
            departure_date = timezone.localtime(self.departure_at).date()
            arrival_date = timezone.localtime(self.arrival_at).date()
            if departure_date != arrival_date:
                raise ValidationError({"arrival_at": "Axis n'opère que des trajets de jour, sans trajet de nuit."})

    def __str__(self):
        return f"{self.route} — {timezone.localtime(self.departure_at):%d/%m/%Y %H:%M}"


class FareRule(TimeStampedModel):
    class RuleType(models.TextChoices):
        STANDARD = "STANDARD", "Tarif standard"
        ADVANCE = "ADVANCE", "Réservation anticipée"
        SAME_DAY = "SAME_DAY", "Jour du départ"
        PROMOTION = "PROMOTION", "Promotion"

    route = models.ForeignKey(Route, on_delete=models.CASCADE, related_name="fare_rules")
    name = models.CharField(max_length=120)
    rule_type = models.CharField(max_length=20, choices=RuleType.choices, default=RuleType.STANDARD)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="XOF")
    advance_days = models.PositiveIntegerField(null=True, blank=True)
    valid_from = models.DateTimeField(null=True, blank=True)
    valid_until = models.DateTimeField(null=True, blank=True)
    active = models.BooleanField(default=True)
    priority = models.PositiveIntegerField(default=100)

    class Meta:
        ordering = ["priority", "name"]

    def clean(self):
        super().clean()
        if self.rule_type == self.RuleType.ADVANCE and self.advance_days is None:
            raise ValidationError({"advance_days": "Le délai doit être configuré pour un tarif anticipé."})
        if self.valid_from and self.valid_until and self.valid_until <= self.valid_from:
            raise ValidationError({"valid_until": "La fin de validité doit être postérieure au début."})

    def __str__(self):
        return f"{self.route} — {self.name}"


class FeatureFlag(TimeStampedModel):
    class Key(models.TextChoices):
        TEMPORAL_PRICING = "TEMPORAL_PRICING", "Tarification temporelle"
        LOYALTY = "LOYALTY", "Programme de fidélité"
        MOBILE_MONEY = "MOBILE_MONEY", "Paiement Mobile Money"
        BUSINESS_ACCOUNTS = "BUSINESS_ACCOUNTS", "Comptes entreprises / ONG"
        BUS_TO_CAR = "BUS_TO_CAR", "Suggestion Bus → Voiture"
        WALLET = "WALLET", "Portefeuille numérique"

    key = models.CharField(max_length=40, choices=Key.choices, unique=True)
    enabled = models.BooleanField(default=False)
    configuration = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["key"]

    def __str__(self):
        return self.get_key_display()


class SystemSetting(TimeStampedModel):
    key = models.CharField(max_length=80, unique=True)
    value = models.JSONField()
    description = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["key"]

    def __str__(self):
        return self.key


class Seat(TimeStampedModel):
    class Status(models.TextChoices):
        AVAILABLE = "AVAILABLE", "Libre"
        HELD = "HELD", "Réservé temporairement"
        PAID = "PAID", "Payé"

    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="seats")
    number = models.CharField(max_length=20)
    row = models.PositiveIntegerField(null=True, blank=True)
    column = models.PositiveIntegerField(null=True, blank=True)
    allowed_passenger_types = models.JSONField(
        default=list,
        blank=True,
        help_text="Types de passagers autorisés (ADULT, CHILD). Une liste vide autorise tous les types.",
    )
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.AVAILABLE, db_index=True)
    hold_expires_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["row", "column", "number"]
        constraints = [models.UniqueConstraint(fields=["trip", "number"], name="unique_seat_per_trip")]

    def __str__(self):
        return f"{self.trip} · siège {self.number}"


class Booking(TimeStampedModel):
    class Status(models.TextChoices):
        HELD = "HELD", "Réservation temporaire"
        CONFIRMED = "CONFIRMED", "Confirmée"
        CANCELLED = "CANCELLED", "Annulée"
        EXPIRED = "EXPIRED", "Expirée"

    reference = models.CharField(max_length=40, unique=True, editable=False)
    trip = models.ForeignKey(Trip, on_delete=models.PROTECT, related_name="bookings")
    customer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="bookings", null=True, blank=True)
    contact_phone = models.CharField(max_length=32, blank=True)
    contact_email = models.EmailField(blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.HELD, db_index=True)
    guest_token_hash = models.CharField(max_length=64, blank=True, editable=False)
    reservation_expires_at = models.DateTimeField(null=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="XOF")

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["customer", "status"])]

    def save(self, *args, **kwargs):
        if not self.reference:
            self.reference = f"AX-RES-{uuid.uuid4().hex[:10].upper()}"
        super().save(*args, **kwargs)

    def __str__(self):
        return self.reference


class Passenger(TimeStampedModel):
    class Type(models.TextChoices):
        ADULT = "ADULT", "Adulte"
        CHILD = "CHILD", "Enfant"

    booking = models.ForeignKey(Booking, on_delete=models.CASCADE, related_name="passengers")
    full_name = models.CharField(max_length=160)
    phone = models.CharField(max_length=32, blank=True)
    passenger_type = models.CharField(max_length=16, choices=Type.choices, default=Type.ADULT)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        return self.full_name


class Ticket(TimeStampedModel):
    class Status(models.TextChoices):
        HELD = "HELD", "Réservé temporairement"
        PAID = "PAID", "Payé / confirmé"
        ISSUED = "ISSUED", "Ticket émis"
        CHECKED = "CHECKED", "Contrôlé"
        COMPLETED = "COMPLETED", "Voyage terminé"
        CANCELLED = "CANCELLED", "Annulé"
        REFUNDED = "REFUNDED", "Remboursé"
        EXPIRED = "EXPIRED", "Expiré"

    class Channel(models.TextChoices):
        ONLINE = "ONLINE", "En ligne"
        COUNTER = "COUNTER", "Guichet"

    reference = models.CharField(max_length=40, unique=True, editable=False)
    trip = models.ForeignKey(Trip, on_delete=models.PROTECT, related_name="tickets")
    seat = models.ForeignKey(Seat, on_delete=models.PROTECT, related_name="tickets")
    booking = models.ForeignKey(
        Booking, on_delete=models.PROTECT, related_name="tickets", null=True, blank=True
    )
    passenger = models.OneToOneField(
        Passenger, on_delete=models.PROTECT, related_name="ticket", null=True, blank=True
    )
    customer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="tickets", null=True, blank=True)
    passenger_name = models.CharField(max_length=160)
    passenger_phone = models.CharField(max_length=32, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.HELD, db_index=True)
    qr_token = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    channel = models.CharField(max_length=16, choices=Channel.choices, default=Channel.ONLINE)
    reservation_expires_at = models.DateTimeField(null=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="XOF")

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["trip", "status"])]

    def save(self, *args, **kwargs):
        if not self.reference:
            self.reference = f"AX-{timezone.now():%Y%m%d}-{uuid.uuid4().hex[:8].upper()}"
        super().save(*args, **kwargs)

    def __str__(self):
        return self.reference


class TicketStatusHistory(models.Model):
    ticket = models.ForeignKey(Ticket, on_delete=models.CASCADE, related_name="status_history")
    from_status = models.CharField(max_length=20, blank=True)
    to_status = models.CharField(max_length=20, choices=Ticket.Status.choices)
    changed_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)
    changed_at = models.DateTimeField(auto_now_add=True)
    note = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["changed_at"]


class TicketControl(models.Model):
    class Method(models.TextChoices):
        QR = "QR", "QR code"
        MANUAL = "MANUAL", "Validation manuelle"

    class Result(models.TextChoices):
        ACCEPTED = "ACCEPTED", "Accepté"
        REJECTED = "REJECTED", "Rejeté"
        ALREADY_USED = "ALREADY_USED", "Déjà utilisé"

    ticket = models.ForeignKey(Ticket, on_delete=models.CASCADE, related_name="controls")
    controller = models.ForeignKey(User, on_delete=models.PROTECT, related_name="ticket_controls")
    controlled_at = models.DateTimeField(auto_now_add=True)
    method = models.CharField(max_length=16, choices=Method.choices)
    result = models.CharField(max_length=20, choices=Result.choices)
    note = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["-controlled_at"]


class Parcel(TimeStampedModel):
    class Status(models.TextChoices):
        REGISTERED = "REGISTERED", "Enregistré"
        DEPOSITED = "DEPOSITED", "Déposé"
        ACCEPTED = "ACCEPTED", "Accepté"
        ASSIGNED = "ASSIGNED", "Affecté au voyage"
        LOADED = "LOADED", "Chargé"
        IN_TRANSIT = "IN_TRANSIT", "En transit"
        ARRIVED = "ARRIVED", "Arrivé"
        READY_FOR_PICKUP = "READY_FOR_PICKUP", "Disponible au retrait"
        PICKED_UP = "PICKED_UP", "Retiré"

    tracking_number = models.CharField(max_length=40, unique=True, editable=False)
    customer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="parcels", null=True, blank=True)
    sender_name = models.CharField(max_length=160)
    sender_phone = models.CharField(max_length=32)
    recipient_name = models.CharField(max_length=160)
    recipient_phone = models.CharField(max_length=32)
    origin = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="parcels_sent")
    destination = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="parcels_received")
    trip = models.ForeignKey(Trip, on_delete=models.PROTECT, related_name="parcels", null=True, blank=True)
    description = models.TextField()
    weight_kg = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.REGISTERED, db_index=True)
    proof_of_deposit = models.FileField(upload_to="parcel-proofs/", null=True, blank=True)
    pickup_recipient_identity = models.CharField(max_length=255, blank=True)
    channel = models.CharField(max_length=16, choices=Ticket.Channel.choices, default=Ticket.Channel.ONLINE)
    amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    currency = models.CharField(max_length=3, default="XOF")

    class Meta:
        ordering = ["-created_at"]

    def clean(self):
        super().clean()
        if self.origin_id and self.destination_id and self.origin_id == self.destination_id:
            raise ValidationError({"destination": "L'origine et la destination doivent être différentes."})
        if self.trip_id and (
            self.trip.route.origin_id != self.origin_id or self.trip.route.destination_id != self.destination_id
        ):
            raise ValidationError({"trip": "Le trajet affecté ne correspond pas au parcours du colis."})

    def save(self, *args, **kwargs):
        if not self.tracking_number:
            self.tracking_number = f"AX-COL-{uuid.uuid4().hex[:10].upper()}"
        super().save(*args, **kwargs)

    def __str__(self):
        return self.tracking_number


class ParcelStatusHistory(models.Model):
    parcel = models.ForeignKey(Parcel, on_delete=models.CASCADE, related_name="status_history")
    from_status = models.CharField(max_length=24, blank=True)
    to_status = models.CharField(max_length=24, choices=Parcel.Status.choices)
    changed_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)
    changed_at = models.DateTimeField(auto_now_add=True)
    note = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["changed_at"]


class RentalBooking(TimeStampedModel):
    class Status(models.TextChoices):
        REQUESTED = "REQUESTED", "Demandée"
        CONFIRMED = "CONFIRMED", "Confirmée"
        ACTIVE = "ACTIVE", "En cours"
        COMPLETED = "COMPLETED", "Terminée"
        CANCELLED = "CANCELLED", "Annulée"

    reference = models.CharField(max_length=40, unique=True, editable=False)
    vehicle = models.ForeignKey(Vehicle, on_delete=models.PROTECT, related_name="rental_bookings")
    customer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="rental_bookings")
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField()
    with_driver = models.BooleanField(default=False)
    identity_document = models.FileField(upload_to="rental-documents/identity/", null=True, blank=True)
    driving_licence = models.FileField(upload_to="rental-documents/licence/", null=True, blank=True)
    deposit_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    currency = models.CharField(max_length=3, default="XOF")
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.REQUESTED, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def clean(self):
        super().clean()
        if self.vehicle_id and self.vehicle.category != Vehicle.Category.RENTAL:
            raise ValidationError({"vehicle": "Seul un véhicule de location peut être réservé."})
        if self.ends_at <= self.starts_at:
            raise ValidationError({"ends_at": "La fin de location doit être postérieure au début."})
        if self.with_driver and self.vehicle_id and not self.vehicle.driver_available:
            raise ValidationError({"with_driver": "Ce véhicule n'est pas configurable avec chauffeur."})

    def save(self, *args, **kwargs):
        if not self.reference:
            self.reference = f"AX-LOC-{uuid.uuid4().hex[:10].upper()}"
        super().save(*args, **kwargs)

    def __str__(self):
        return self.reference


class PaymentMethod(TimeStampedModel):
    code = models.SlugField(max_length=40, unique=True)
    label = models.CharField(max_length=100)
    active = models.BooleanField(default=False)
    fee_percentage = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=Decimal("0.00"),
        help_text="Taux de frais de transaction en pourcentage (ex: 1.80 pour 1.8%)",
    )
    configuration = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["label"]

    def __str__(self):
        return self.label


class Transaction(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "PENDING", "En attente"
        SUCCEEDED = "SUCCEEDED", "Réussie"
        FAILED = "FAILED", "Échouée"
        REFUNDED = "REFUNDED", "Remboursée"

    reference = models.CharField(max_length=40, unique=True, editable=False)
    payment_method = models.ForeignKey(PaymentMethod, on_delete=models.PROTECT, related_name="transactions")
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="XOF")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING, db_index=True)
    ticket = models.ForeignKey(Ticket, on_delete=models.PROTECT, related_name="transactions", null=True, blank=True)
    parcel = models.ForeignKey(Parcel, on_delete=models.PROTECT, related_name="transactions", null=True, blank=True)
    rental = models.ForeignKey(
        RentalBooking, on_delete=models.PROTECT, related_name="transactions", null=True, blank=True
    )
    external_reference = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=(
                    (Q(ticket__isnull=False) & Q(parcel__isnull=True) & Q(rental__isnull=True))
                    | (Q(ticket__isnull=True) & Q(parcel__isnull=False) & Q(rental__isnull=True))
                    | (Q(ticket__isnull=True) & Q(parcel__isnull=True) & Q(rental__isnull=False))
                ),
                name="transaction_exactly_one_target",
            )
        ]

    def clean(self):
        super().clean()
        targets = [self.ticket_id, self.parcel_id, self.rental_id]
        if sum(target is not None for target in targets) != 1:
            raise ValidationError("Une transaction doit être associée à un seul billet, colis ou location.")

    def save(self, *args, **kwargs):
        if not self.reference:
            self.reference = f"AX-PAY-{uuid.uuid4().hex[:10].upper()}"
        super().save(*args, **kwargs)

    def __str__(self):
        return self.reference


class PaymentReceipt(TimeStampedModel):
    """Preuve de paiement vérifiée côté serveur. Aucun billet n'est émis sans elle."""

    class Source(models.TextChoices):
        CLIENT = "CLIENT", "Confirmation client"
        WEBHOOK = "WEBHOOK", "Webhook prestataire"
        COUNTER = "COUNTER", "Encaissement guichet"

    provider = models.CharField(max_length=40)
    external_id = models.CharField(max_length=120)
    booking = models.ForeignKey(
        Booking, on_delete=models.PROTECT, related_name="payment_receipts", null=True, blank=True
    )
    ticket = models.ForeignKey(
        Ticket, on_delete=models.PROTECT, related_name="payment_receipts", null=True, blank=True
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="XOF")
    source = models.CharField(max_length=16, choices=Source.choices)
    recorded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["provider", "external_id"], name="unique_provider_payment"),
            models.UniqueConstraint(
                fields=["booking"], condition=Q(booking__isnull=False), name="unique_receipt_per_booking"
            ),
            models.UniqueConstraint(
                fields=["ticket"], condition=Q(ticket__isnull=False), name="unique_receipt_per_ticket"
            ),
            models.CheckConstraint(
                condition=(
                    (Q(booking__isnull=False) & Q(ticket__isnull=True))
                    | (Q(booking__isnull=True) & Q(ticket__isnull=False))
                ),
                name="receipt_exactly_one_target",
            ),
        ]

    def __str__(self):
        return f"{self.provider}:{self.external_id}"
