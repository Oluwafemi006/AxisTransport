"""Tableau de bord et bilan : bornes du jour en heure du Bénin, billets annulés ou remboursés non comptés, accès admin."""
from datetime import datetime, timedelta, timezone as dt_timezone

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core import reporting
from apps.core.models import Parcel, PaymentMethod, Ticket, TicketControl, TicketStatusHistory, Transaction, User
from apps.core.services import transition_ticket

from .factories import build_operational_context

SALES = "/api/v1/staff/sales/"


class DashboardReportTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        self.admin = self.context["admin"]
        self.controller = self.context["controller"]
        self.counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces TEST", active=True)
        self.seats = list(self.trip.seats.order_by("number"))
        self.today = timezone.localdate()

    def sell(self, seat, key):
        self.client.force_authenticate(self.counter)
        response = self.client.post(f"{SALES}sell/", {
            "idempotency_key": key, "trip": self.trip.pk, "seat": seat.pk, "passenger_name": "Passager TEST",
            "passenger_phone": "90000000", "payment_method": self.cash.pk,
        }, format="json")
        self.assertIn(response.status_code, {200, 201}, response.content)
        self.assertIsNone(response.json().get("payment_error"), response.content)
        return Ticket.objects.get(booking_id=response.json()["booking"]["id"], seat=seat)

    def scan(self, ticket, when=None):
        control = TicketControl.objects.create(
            ticket=ticket, controller=self.controller, method=TicketControl.Method.QR, result=TicketControl.Result.ACCEPTED
        )
        if when:
            TicketControl.objects.filter(pk=control.pk).update(controlled_at=when)
        ticket.refresh_from_db()
        if ticket.status == Ticket.Status.ISSUED:
            transition_ticket(ticket, Ticket.Status.CHECKED, actor=self.controller)

    def dashboard(self, **params):
        self.client.force_authenticate(self.admin)
        response = self.client.get("/api/v1/dashboard/", params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def report(self, **params):
        self.client.force_authenticate(self.admin)
        response = self.client.get("/api/v1/dashboard/report/", params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def test_today_counts_sold_scanned_and_gross_revenue(self):
        t1 = self.sell(self.seats[0], "vente-test-0001")
        self.sell(self.seats[1], "vente-test-0002")
        self.scan(t1)
        data = self.dashboard()
        self.assertEqual(data["tickets"]["sold"], 2)
        self.assertEqual(data["tickets"]["checked"], 1)
        self.assertEqual(data["revenue"]["total"], 2000)
        self.assertEqual(data["today"]["tickets_sold"], 2)
        self.assertEqual(data["today"]["tickets_scanned"], 1)
        self.assertEqual(data["today"]["gross_revenue"], 2000)
        self.assertEqual(data["all_time"]["tickets_sold"], 2)

    def test_refunded_and_cancelled_tickets_are_not_sold_but_revenue_stays_gross(self):
        refunded = self.sell(self.seats[0], "vente-test-0001")
        cancelled = self.sell(self.seats[1], "vente-test-0002")
        self.sell(self.seats[2], "vente-test-0003")
        transition_ticket(refunded, Ticket.Status.REFUNDED, actor=self.admin, note="TEST", manual=True)
        transition_ticket(cancelled, Ticket.Status.CANCELLED, actor=self.admin, note="TEST", manual=True)
        data = self.dashboard()
        self.assertEqual(data["tickets"]["sold"], 1)
        self.assertEqual(data["tickets"]["refunded"], 1)
        # Encaissement brut : les 3 transactions restent SUCCEEDED, rien n'est déduit.
        self.assertEqual(data["revenue"]["total"], 3000)
        self.assertEqual(Transaction.objects.filter(status=Transaction.Status.SUCCEEDED).count(), 3)

    def test_day_bounds_are_benin_midnight(self):
        ticket = self.sell(self.seats[0], "vente-test-0001")
        # Paiement à 23 h 30 UTC la veille = 00 h 30 au Bénin aujourd'hui : compté aujourd'hui.
        at = datetime.combine(self.today - timedelta(days=1), datetime.min.time(), tzinfo=dt_timezone.utc).replace(hour=23, minute=30)
        TicketStatusHistory.objects.filter(ticket=ticket, to_status=Ticket.Status.PAID).update(changed_at=at)
        self.assertEqual(reporting.sold_tickets_count(self.today, self.today), 1)
        yesterday = self.today - timedelta(days=1)
        self.assertEqual(reporting.sold_tickets_count(yesterday, yesterday), 0)
        # 22 h 59 UTC la veille = 23 h 59 au Bénin la veille : compté la veille.
        TicketStatusHistory.objects.filter(ticket=ticket, to_status=Ticket.Status.PAID).update(changed_at=at.replace(hour=22, minute=59))
        self.assertEqual(reporting.sold_tickets_count(self.today, self.today), 0)
        self.assertEqual(reporting.sold_tickets_count(yesterday, yesterday), 1)

    def test_scanned_ticket_counted_once_at_scan_date(self):
        ticket = self.sell(self.seats[0], "vente-test-0001")
        yesterday_noon = timezone.now() - timedelta(days=1)
        self.scan(ticket, when=yesterday_noon)
        self.scan(ticket)  # deuxième ligne de contrôle acceptée, même billet
        self.assertEqual(reporting.scanned_tickets_count(self.today, self.today), 1)
        self.assertEqual(reporting.scanned_tickets_count(self.today - timedelta(days=1), self.today), 1)
        days = reporting.daily_rows(self.today - timedelta(days=1), self.today)
        self.assertEqual([d["tickets_scanned"] for d in days], [1, 1])

    def test_parcels_exclude_cancelled(self):
        base = dict(
            sender_name="Expéditeur TEST", sender_phone="90000001", recipient_name="Destinataire TEST",
            recipient_phone="90000002", origin=self.context["origin"], destination=self.context["destination"],
        )
        Parcel.objects.create(**base)
        Parcel.objects.create(**base, status=Parcel.Status.CANCELLED)
        data = self.dashboard()
        self.assertEqual(data["parcels_summary"], {"tracked": 1, "cancelled": 1, "picked_up": 0})

    def test_report_default_start_is_oldest_admin_and_rows_cover_period(self):
        oldest = User.objects.create_user(username="admin-ancien", password="TEST-pass-123", role=User.Role.ADMIN)
        joined = timezone.now() - timedelta(days=3)
        User.objects.filter(pk=oldest.pk).update(date_joined=joined)
        self.sell(self.seats[0], "vente-test-0001")
        data = self.report()
        self.assertEqual(data["default_start"], timezone.localdate(joined).isoformat())
        self.assertEqual(data["period"]["start"], timezone.localdate(joined).isoformat())
        self.assertEqual(len(data["days"]), 4)
        self.assertEqual(data["headline"]["tickets_sold"], 1)
        self.assertEqual(data["revenue"]["cash_or_other"], 1000)
        self.assertEqual(data["revenue"]["mobile_money"], 0)
        self.assertEqual(data["trips"][0]["tickets_sold"], 1)
        agent = next(row for row in data["agents"] if row["id"] == self.counter.pk)
        self.assertEqual(agent["tickets_sold"], 1)
        self.assertEqual(agent["cash_fcfa"], 1000)
        self.assertNotIn("passenger_name", str(data))

    def test_report_rejects_bad_dates(self):
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.get("/api/v1/dashboard/report/", {"start": "2026-13-01"}).status_code, 400)
        self.assertEqual(
            self.client.get("/api/v1/dashboard/report/", {"start": "2026-11-10", "end": "2026-11-01"}).status_code, 400
        )

    def test_refused_to_non_admins(self):
        for user in (self.counter, self.controller, self.context["client"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get("/api/v1/dashboard/").status_code, 403)
            self.assertEqual(self.client.get("/api/v1/dashboard/report/").status_code, 403)
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get("/api/v1/dashboard/report/").status_code, 401)
