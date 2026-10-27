from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import (
    BoardingPoint,
    Booking,
    FareRule,
    FeatureFlag,
    Location,
    Parcel,
    ParcelStatusHistory,
    PaymentMethod,
    PaymentAttempt,
    PaymentIncident,
    PaymentReceipt,
    SegmentFareChange,
    StaffInvitation,
    Passenger,
    RentalBooking,
    Route,
    RouteStop,
    Seat,
    SystemSetting,
    Ticket,
    TicketControl,
    TicketStatusHistory,
    Transaction,
    Trip,
    User,
    Vehicle,
    WeeklySchedule,
)


@admin.register(User)
class AxisUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (("Axis Transport", {"fields": ("role", "phone")}),)
    add_fieldsets = UserAdmin.add_fieldsets + (("Axis Transport", {"fields": ("role", "phone")}),)
    list_display = ("username", "email", "first_name", "last_name", "role", "is_active")
    list_filter = UserAdmin.list_filter + ("role",)


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = ("route", "departure_at", "vehicle", "status")
    list_filter = ("status", "route", "vehicle")
    date_hierarchy = "departure_at"


@admin.register(WeeklySchedule)
class WeeklyScheduleAdmin(admin.ModelAdmin):
    list_display = ("day_of_week", "route", "departure_time", "vehicle", "is_active")
    list_filter = ("is_active", "day_of_week", "route")


@admin.register(Ticket)
class TicketAdmin(admin.ModelAdmin):
    list_display = ("reference", "trip", "origin", "destination", "seat", "passenger_name", "status", "channel", "amount")
    list_filter = ("status", "channel", "origin", "destination", "trip")
    search_fields = ("reference", "passenger_name", "passenger_phone")


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("reference", "trip", "origin", "destination", "customer", "status", "amount", "currency", "reservation_expires_at")
    list_filter = ("status", "origin", "destination", "trip")
    search_fields = ("reference", "contact_phone", "contact_email", "customer__username")


@admin.register(Passenger)
class PassengerAdmin(admin.ModelAdmin):
    list_display = ("full_name", "booking", "passenger_type", "phone")
    list_filter = ("passenger_type",)
    search_fields = ("full_name", "phone", "booking__reference")


@admin.register(Parcel)
class ParcelAdmin(admin.ModelAdmin):
    list_display = ("tracking_number", "origin", "destination", "recipient_name", "status", "trip")
    list_filter = ("status", "origin", "destination")
    search_fields = ("tracking_number", "sender_name", "recipient_name")


@admin.register(Vehicle)
class VehicleAdmin(admin.ModelAdmin):
    list_display = ("name", "category", "registration_number", "capacity", "state", "base_location")
    list_filter = ("category", "state", "base_location")


@admin.register(PaymentReceipt)
class PaymentReceiptAdmin(admin.ModelAdmin):
    list_display = ("provider", "external_id", "booking", "ticket", "amount", "currency", "source", "refund_due", "created_at")
    list_filter = ("refund_due", "provider", "source")
    search_fields = ("external_id", "booking__reference", "ticket__reference")


@admin.register(PaymentAttempt)
class PaymentAttemptAdmin(admin.ModelAdmin):
    list_display = ("provider", "external_id", "booking", "amount", "outcome", "provider_status", "checks", "last_checked_at", "created_at")
    list_filter = ("outcome", "provider")
    search_fields = ("external_id", "booking__reference")
    readonly_fields = ("provider", "external_id", "booking", "ticket", "amount", "currency", "checks", "last_checked_at")


@admin.register(SegmentFareChange)
class SegmentFareChangeAdmin(admin.ModelAdmin):
    list_display = ("created_at", "fare", "old_amount", "new_amount", "changed_by")
    readonly_fields = ("fare", "old_amount", "new_amount", "changed_by")

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(PaymentIncident)
class PaymentIncidentAdmin(admin.ModelAdmin):
    list_display = ("created_at", "source", "event", "external_id", "amount", "currency", "amount_verified", "booking", "handled", "reason")
    list_filter = ("handled", "source", "provider")
    search_fields = ("external_id", "booking__reference", "reason")
    readonly_fields = ("source", "provider", "event", "external_id", "amount", "currency", "amount_verified", "booking", "reason")


@admin.register(StaffInvitation)
class StaffInvitationAdmin(admin.ModelAdmin):
    list_display = ("email", "group", "expires_at", "is_used", "created_at", "invited_by")
    list_filter = ("group", "is_used")
    search_fields = ("email", "token")
    readonly_fields = ("token", "is_used", "created_at", "invited_by")
    actions = ["resend_invitation_email"]

    def save_model(self, request, obj, form, change):
        if not change and not obj.invited_by and request.user.is_authenticated:
            obj.invited_by = request.user
        super().save_model(request, obj, form, change)
        if not change:
            # Envoi réel de l'e-mail lors de la création
            obj.send_invitation_email()

    @admin.action(description="Renvoyer l'e-mail d'invitation")
    def resend_invitation_email(self, request, queryset):
        sent = 0
        for invite in queryset:
            if not invite.is_used:
                invite.send_invitation_email()
                sent += 1
        self.message_user(request, f"{sent} invitation(s) renvoyée(s) avec succès.")


class RouteStopInline(admin.TabularInline):
    model = RouteStop
    fields = ["position", "location", "offset_minutes"]
    extra = 1
    ordering = ["position"]


@admin.register(Route)
class RouteAdmin(admin.ModelAdmin):
    list_display = ("origin", "destination", "active", "created_at")
    list_filter = ("active",)
    inlines = [RouteStopInline]


@admin.register(RouteStop)
class RouteStopAdmin(admin.ModelAdmin):
    list_display = ("route", "position", "location", "offset_minutes")
    list_filter = ("route",)
    ordering = ("route", "position")


@admin.register(BoardingPoint)
class BoardingPointAdmin(admin.ModelAdmin):
    list_display = ("name", "location", "order", "active", "updated_at")
    list_filter = ("active", "location")
    ordering = ("location__name", "order", "name")


admin.site.register(
    [
        Location,
        Seat,
        FareRule,
        FeatureFlag,
        SystemSetting,
        TicketStatusHistory,
        TicketControl,
        ParcelStatusHistory,
        RentalBooking,
        PaymentMethod,
        Transaction,
    ]
)
