"""
Chiffres du tableau de bord et du bilan administrateur.

Une seule définition par chiffre, partagée par l'accueil (« Aujourd'hui », « Cumul global »)
et par le bilan sur une période. Les bornes d'une période sont des jours entiers en heure du Bénin
(fuseau du projet, `TIME_ZONE`) : de minuit le premier jour à minuit après le dernier jour.

Définitions (décisions d'Eddy, novembre 2026) :
- billet vendu : billet au statut PAID, ISSUED, CHECKED ou COMPLETED, daté par son passage au
  statut PAID (`TicketStatusHistory.to_status = PAID`, un seul passage possible par billet) ;
- billet scanné : contrôle accepté (`TicketControl.result = ACCEPTED`) daté par `controlled_at`,
  un billet compté une seule fois par période ;
- encaissement brut : somme des `Transaction` au statut SUCCEEDED, datées par la transaction ;
  les remboursements ne sont pas déduits (aucun mécanisme de remboursement n'existe) ;
- billet remboursé : passage au statut REFUNDED, daté par ce passage ;
- colis suivi : colis créé dans la période, hors annulés ; les annulés sont comptés à part ;
- location : demande créée dans la période, par statut ; le montant affiché est le total prévu,
  pas un encaissement (aucune transaction de location n'est enregistrée par le code).
"""
from datetime import date, datetime, time, timedelta
from django.db.models import Count, Q, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone

from .models import (
    Parcel,
    ParcelStatusHistory,
    RentalBooking,
    Ticket,
    TicketControl,
    TicketStatusHistory,
    Transaction,
    Trip,
    User,
)
from .payments import ONLINE_PROVIDERS

SOLD_STATUSES = (Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CHECKED, Ticket.Status.COMPLETED)


def period_bounds(start: date, end: date):
    """Bornes [début, fin) en heure du Bénin : minuit du premier jour, minuit après le dernier."""
    tz = timezone.get_current_timezone()
    first = timezone.make_aware(datetime.combine(start, time.min), tz)
    after = timezone.make_aware(datetime.combine(end + timedelta(days=1), time.min), tz)
    return first, after


def _local_date(field):
    return TruncDate(field, tzinfo=timezone.get_current_timezone())


def _int(value):
    return int(value or 0)


# --- Billets -------------------------------------------------------------

def sold_ticket_events(start: date, end: date):
    """Passages au statut PAID, dans la période, de billets encore vendus (non annulés ni remboursés)."""
    first, after = period_bounds(start, end)
    return TicketStatusHistory.objects.filter(
        to_status=Ticket.Status.PAID,
        changed_at__gte=first,
        changed_at__lt=after,
        ticket__status__in=SOLD_STATUSES,
    )


def sold_tickets_count(start: date, end: date) -> int:
    return sold_ticket_events(start, end).values("ticket").distinct().count()


def scanned_ticket_controls(start: date, end: date):
    first, after = period_bounds(start, end)
    return TicketControl.objects.filter(
        result=TicketControl.Result.ACCEPTED, controlled_at__gte=first, controlled_at__lt=after
    )


def scanned_tickets_count(start: date, end: date) -> int:
    return scanned_ticket_controls(start, end).values("ticket").distinct().count()


def refunded_tickets_count(start: date, end: date) -> int:
    first, after = period_bounds(start, end)
    return (
        TicketStatusHistory.objects.filter(
            to_status=Ticket.Status.REFUNDED, changed_at__gte=first, changed_at__lt=after
        )
        .values("ticket")
        .distinct()
        .count()
    )


# --- Encaissements -------------------------------------------------------

def succeeded_transactions(start: date, end: date):
    first, after = period_bounds(start, end)
    return Transaction.objects.filter(
        status=Transaction.Status.SUCCEEDED, created_at__gte=first, created_at__lt=after
    )


def gross_revenue(start: date, end: date) -> int:
    """Encaissements bruts en FCFA : remboursements non déduits."""
    return _int(succeeded_transactions(start, end).aggregate(total=Sum("amount"))["total"])


def revenue_breakdown(start: date, end: date) -> dict:
    """Par objet (billets, colis, locations) et par canal (Mobile Money en ligne ou espèces et autres)."""
    rows = succeeded_transactions(start, end).values("payment_method__code").annotate(
        tickets=Sum("amount", filter=Q(ticket__isnull=False)),
        parcels=Sum("amount", filter=Q(parcel__isnull=False)),
        rentals=Sum("amount", filter=Q(rental__isnull=False)),
        total=Sum("amount"),
    )
    out = {"tickets": 0, "parcels": 0, "rentals": 0, "mobile_money": 0, "cash_or_other": 0, "total": 0}
    for row in rows:
        out["tickets"] += _int(row["tickets"])
        out["parcels"] += _int(row["parcels"])
        out["rentals"] += _int(row["rentals"])
        total = _int(row["total"])
        out["total"] += total
        if (row["payment_method__code"] or "").upper() in ONLINE_PROVIDERS:
            out["mobile_money"] += total
        else:
            out["cash_or_other"] += total
    return out


# --- Colis et locations --------------------------------------------------

def parcels_summary(start: date, end: date) -> dict:
    first, after = period_bounds(start, end)
    rows = Parcel.objects.filter(created_at__gte=first, created_at__lt=after).aggregate(
        total=Count("id"),
        cancelled=Count("id", filter=Q(status=Parcel.Status.CANCELLED)),
        picked_up=Count("id", filter=Q(status=Parcel.Status.PICKED_UP)),
    )
    return {
        "tracked": rows["total"] - rows["cancelled"],
        "cancelled": rows["cancelled"],
        "picked_up": rows["picked_up"],
    }


def rentals_summary(start: date, end: date) -> dict:
    first, after = period_bounds(start, end)
    qs = RentalBooking.objects.filter(created_at__gte=first, created_at__lt=after)
    by_status = {row["status"]: row["count"] for row in qs.values("status").annotate(count=Count("id"))}
    planned = qs.exclude(status=RentalBooking.Status.CANCELLED).aggregate(total=Sum("total_amount"))["total"]
    return {
        "requested": qs.count(),
        "by_status": [
            {"status": value, "label": label, "count": by_status.get(value, 0)}
            for value, label in RentalBooking.Status.choices
        ],
        # Total prévu des demandes non annulées : aucune transaction de location n'existe en base.
        "planned_amount": _int(planned),
    }


# --- Agrégats ------------------------------------------------------------

def headline(start: date, end: date) -> dict:
    """Les chiffres principaux, mêmes définitions partout."""
    return {
        "tickets_sold": sold_tickets_count(start, end),
        "tickets_scanned": scanned_tickets_count(start, end),
        "tickets_refunded": refunded_tickets_count(start, end),
        "gross_revenue": gross_revenue(start, end),
        "parcels": parcels_summary(start, end),
    }


def daily_rows(start: date, end: date) -> list:
    """Une ligne par jour de la période, en heure du Bénin, y compris les jours sans activité."""
    sold = {
        r["day"]: r["n"]
        for r in sold_ticket_events(start, end).annotate(day=_local_date("changed_at")).values("day")
        .annotate(n=Count("ticket", distinct=True))
    }
    scanned = {
        r["day"]: r["n"]
        for r in scanned_ticket_controls(start, end).annotate(day=_local_date("controlled_at")).values("day")
        .annotate(n=Count("ticket", distinct=True))
    }
    first, after = period_bounds(start, end)
    refunded = {
        r["day"]: r["n"]
        for r in TicketStatusHistory.objects.filter(
            to_status=Ticket.Status.REFUNDED, changed_at__gte=first, changed_at__lt=after
        ).annotate(day=_local_date("changed_at")).values("day").annotate(n=Count("ticket", distinct=True))
    }
    revenue = {
        r["day"]: _int(r["total"])
        for r in succeeded_transactions(start, end).annotate(day=_local_date("created_at")).values("day")
        .annotate(total=Sum("amount"))
    }
    parcels = {
        r["day"]: r["n"]
        for r in Parcel.objects.filter(created_at__gte=first, created_at__lt=after)
        .exclude(status=Parcel.Status.CANCELLED)
        .annotate(day=_local_date("created_at")).values("day").annotate(n=Count("id"))
    }
    rows = []
    day = start
    while day <= end:
        rows.append(
            {
                "date": day,
                "tickets_sold": sold.get(day, 0),
                "tickets_scanned": scanned.get(day, 0),
                "tickets_refunded": refunded.get(day, 0),
                "gross_revenue": revenue.get(day, 0),
                "parcels_tracked": parcels.get(day, 0),
            }
        )
        day += timedelta(days=1)
    return rows


def trip_rows(start: date, end: date) -> list:
    """Départs de la période (date de départ en heure du Bénin) : vendus, scannés, encaissé."""
    first, after = period_bounds(start, end)
    trips = (
        Trip.objects.filter(departure_at__gte=first, departure_at__lt=after)
        .select_related("route__origin", "route__destination", "vehicle")
        .annotate(
            sold=Count("tickets", filter=Q(tickets__status__in=SOLD_STATUSES), distinct=True),
            scanned=Count(
                "tickets__controls",
                filter=Q(tickets__controls__result=TicketControl.Result.ACCEPTED),
                distinct=True,
            ),
        )
        .order_by("departure_at")
    )
    # L'encaissement par départ est sommé à part : deux jointures « many » dans une même requête
    # multiplieraient les lignes et fausseraient la somme.
    revenue = {
        r["ticket__trip"]: _int(r["total"])
        for r in Transaction.objects.filter(
            status=Transaction.Status.SUCCEEDED, ticket__trip__in=trips.values("id")
        ).values("ticket__trip").annotate(total=Sum("amount"))
    }
    return [
        {
            "id": trip.id,
            "label": trip.route.label,
            "departure_at": trip.departure_at,
            "status": trip.status,
            "status_display": trip.get_status_display(),
            "capacity": trip.vehicle.capacity if trip.vehicle_id else None,
            "tickets_sold": trip.sold,
            "tickets_scanned": trip.scanned,
            "gross_revenue": revenue.get(trip.id, 0),
        }
        for trip in trips
    ]


def agent_rows(start: date, end: date) -> list:
    """Activité du personnel : billets vendus au guichet, scans, colis enregistrés, encaissements.

    Chiffres agrégés par agent (nom d'utilisateur du personnel), sans aucune donnée de passager.
    """
    first, after = period_bounds(start, end)
    staff = User.objects.filter(role__in=[User.Role.COUNTER, User.Role.CONTROLLER, User.Role.ADMIN])
    payments = (
        succeeded_transactions(start, end)
        .filter(ticket__booking__sold_by__isnull=False)
        .values("ticket__booking__sold_by", "payment_method__code")
        .annotate(total=Sum("amount"), tickets=Count("ticket", distinct=True))
    )
    sold, cash, mobile = {}, {}, {}
    for row in payments:
        uid = row["ticket__booking__sold_by"]
        sold[uid] = sold.get(uid, 0) + row["tickets"]
        bucket = mobile if (row["payment_method__code"] or "").upper() in ONLINE_PROVIDERS else cash
        bucket[uid] = bucket.get(uid, 0) + _int(row["total"])
    scans = {
        r["controller"]: r["n"]
        for r in scanned_ticket_controls(start, end).values("controller").annotate(n=Count("ticket", distinct=True))
    }
    parcels = {
        r["changed_by"]: r["n"]
        for r in ParcelStatusHistory.objects.filter(
            to_status=Parcel.Status.REGISTERED, changed_at__gte=first, changed_at__lt=after, changed_by__isnull=False
        ).values("changed_by").annotate(n=Count("parcel", distinct=True))
    }
    rows = []
    for user in staff.order_by("username"):
        row = {
            "id": user.pk,
            "name": user.get_full_name() or user.username,
            "role": user.role,
            "tickets_sold": sold.get(user.pk, 0),
            "tickets_scanned": scans.get(user.pk, 0),
            "parcels_registered": parcels.get(user.pk, 0),
            "cash_fcfa": cash.get(user.pk, 0),
            "mobile_money_fcfa": mobile.get(user.pk, 0),
        }
        if any(row[k] for k in ("tickets_sold", "tickets_scanned", "parcels_registered", "cash_fcfa", "mobile_money_fcfa")):
            rows.append(row)
    return rows


def default_report_start() -> date:
    """Date de création du plus ancien compte administrateur ; à défaut, aujourd'hui."""
    oldest = User.objects.filter(role=User.Role.ADMIN).order_by("date_joined").values_list("date_joined", flat=True).first()
    return timezone.localdate(oldest) if oldest else timezone.localdate()


def all_time_start() -> date:
    """Premier jour connu : plus ancien compte administrateur ou plus ancienne donnée d'activité."""
    candidates = [
        User.objects.filter(role=User.Role.ADMIN).order_by("date_joined").values_list("date_joined", flat=True).first(),
        Ticket.objects.order_by("created_at").values_list("created_at", flat=True).first(),
        Transaction.objects.order_by("created_at").values_list("created_at", flat=True).first(),
        Parcel.objects.order_by("created_at").values_list("created_at", flat=True).first(),
    ]
    known = [timezone.localdate(value) for value in candidates if value]
    return min(known) if known else timezone.localdate()


def report(start: date, end: date) -> dict:
    return {
        "period": {"start": start, "end": end},
        "headline": headline(start, end),
        "revenue": revenue_breakdown(start, end),
        "rentals": rentals_summary(start, end),
        "days": daily_rows(start, end),
        "trips": trip_rows(start, end),
        "agents": agent_rows(start, end),
    }
