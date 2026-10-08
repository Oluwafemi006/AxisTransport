from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import (
    Booking,
    FareRule,
    FeatureFlag,
    Location,
    Parcel,
    ParcelStatusHistory,
    PaymentMethod,
    PaymentReceipt,
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


@admin.register(Ticket)
class TicketAdmin(admin.ModelAdmin):
    list_display = ("reference", "trip", "seat", "passenger_name", "status", "channel", "amount")
    list_filter = ("status", "channel", "trip")
    search_fields = ("reference", "passenger_name", "passenger_phone")


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("reference", "trip", "customer", "status", "amount", "currency", "reservation_expires_at")
    list_filter = ("status", "trip")
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


admin.site.register(
    [
        Location,
        Route,
        Seat,
        FareRule,
        FeatureFlag,
        SystemSetting,
        TicketStatusHistory,
        TicketControl,
        ParcelStatusHistory,
        RentalBooking,
        PaymentMethod,
        PaymentReceipt,
        Transaction,
    ]
)
