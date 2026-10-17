import json
from decimal import Decimal
from types import SimpleNamespace
from unittest import mock

from django.test import TestCase, override_settings
from rest_framework.test import APITestCase

from apps.core.models import AgencyProfile, AgencySettingChange, Booking, PaymentMethod, Tax, Ticket, User
from apps.core.services import tax_breakdown

from .factories import build_operational_context
from .test_payment_security import FEDAPAY_SETTINGS, FETCH, fedapay_transaction, make_booking

# Valeurs fictives, clairement marquées TEST : aucune donnée réelle d'agence dans les tests.
TEST_AGENCY = {
    "legal_name": "TEST Raison sociale",
    "ifu": "TEST-IFU-0000",
    "rccm": "TEST-RCCM-0000",
    "capital": "TEST capital",
    "address": "TEST adresse",
    "phones": "TEST téléphones",
    "email": "test@example.invalid",
    "bank_accounts": "TEST compte bancaire à ne jamais imprimer",
}


def vat(rate="18"):
    return [SimpleNamespace(name="TVA", rate=Decimal(rate))]


class TaxBreakdownTests(TestCase):
    """HT = TTC / (1 + taux), TVA = TTC - HT, arrondis au franc ; TTC = HT + TVA toujours exact."""

    def test_given_examples(self):
        expected = {7500: (6356, 1144), 2000: (1695, 305), 1500: (1271, 229), 4500: (3814, 686), 2500: (2119, 381)}
        for price, (excl, tax) in expected.items():
            with self.subTest(price=price):
                got_excl, lines = tax_breakdown(price, vat())
                self.assertEqual((int(got_excl), lines[0]["amount"]), (excl, tax))
                self.assertEqual(lines[0]["name"], "TVA")
                self.assertEqual(lines[0]["rate"], "18")

    def test_total_is_always_exact(self):
        for price in range(1, 20001, 7):
            excl, lines = tax_breakdown(price, vat())
            self.assertEqual(int(excl) + sum(line["amount"] for line in lines), price)

    def test_without_tax_price_is_unchanged(self):
        self.assertEqual(tax_breakdown(7500, []), (Decimal("7500"), []))
        self.assertEqual(tax_breakdown(7500, vat("0")), (Decimal("7500"), []))

    def test_initial_tax_is_vat_18_included(self):
        self.assertEqual(
            list(Tax.objects.values_list("name", "rate", "active", "included")), [("TVA", Decimal("18.00"), True, True)]
        )
        excl, lines = tax_breakdown(7500)
        self.assertEqual((int(excl), lines[0]["amount"]), (6356, 1144))

    def test_inactive_or_added_taxes_are_not_counted(self):
        Tax.objects.update(active=False)
        self.assertEqual(tax_breakdown(7500), (Decimal("7500"), []))
        Tax.objects.update(active=True, included=False)
        self.assertEqual(tax_breakdown(7500), (Decimal("7500"), []))


class TicketTaxSnapshotTests(TestCase):
    def test_sold_ticket_keeps_its_rate_and_amounts(self):
        context = build_operational_context()
        booking = make_booking(context, seats=1)
        ticket = booking.tickets.get()
        self.assertEqual((ticket.amount, ticket.price_excl_tax), (Decimal("1000"), Decimal("847")))
        self.assertEqual(ticket.tax_lines, [{"name": "TVA", "rate": "18", "amount": 153}])
        Tax.objects.update(rate=Decimal("10"))
        ticket.refresh_from_db()
        self.assertEqual(ticket.price_excl_tax, Decimal("847"))
        self.assertEqual(ticket.tax_lines[0]["amount"], 153)
        later = make_booking(context, seats=1, offset=1).tickets.get()
        self.assertEqual(later.tax_lines[0]["amount"], 91)  # 1000 / 1,10 = 909 ; 1000 - 909 = 91


class AgencyAndTaxAdminTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)

    def test_agency_is_empty_by_default(self):
        self.client.force_authenticate(self.context["admin"])
        data = self.client.get("/api/v1/agency-profile/").json()
        for field in AgencyProfile.EDITABLE_FIELDS:
            self.assertEqual(data[field], "", field)

    def test_admin_change_is_logged_with_old_and_new_content(self):
        admin = self.context["admin"]
        self.client.force_authenticate(admin)
        response = self.client.patch("/api/v1/agency-profile/", {"legal_name": "  TEST Raison sociale "}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["legal_name"], "TEST Raison sociale")
        entry = AgencySettingChange.objects.get()
        self.assertEqual(entry.kind, AgencySettingChange.Kind.AGENCY)
        self.assertEqual((entry.old_value["legal_name"], entry.new_value["legal_name"]), ("", "TEST Raison sociale"))
        self.assertEqual(entry.changed_by, admin)
        # Même contenu : rien n'est journalisé.
        self.client.patch("/api/v1/agency-profile/", {"legal_name": "TEST Raison sociale"}, format="json")
        self.assertEqual(AgencySettingChange.objects.count(), 1)
        log = self.client.get("/api/v1/agency-changes/").json()
        rows = log["results"] if isinstance(log, dict) else log
        self.assertEqual(rows[0]["label"], "Informations de l'agence")

    def test_only_admin_can_read_or_change(self):
        for user in (self.context["client"], self.counter, self.context["controller"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get("/api/v1/agency-profile/").status_code, 403, user.role)
            self.assertEqual(self.client.patch("/api/v1/agency-profile/", {"ifu": "x"}, format="json").status_code, 403)
            self.assertEqual(self.client.get("/api/v1/taxes/").status_code, 403)
            self.assertEqual(self.client.get("/api/v1/agency-changes/").status_code, 403)
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get("/api/v1/agency-profile/").status_code, 401)
        self.assertEqual(AgencyProfile.objects.exclude(ifu="").count(), 0)

    def test_tax_change_is_logged_and_validated(self):
        self.client.force_authenticate(self.context["admin"])
        tax = Tax.objects.get()
        self.assertEqual(self.client.patch(f"/api/v1/taxes/{tax.pk}/", {"rate": "100"}, format="json").status_code, 400)
        response = self.client.patch(f"/api/v1/taxes/{tax.pk}/", {"rate": "10.00"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        entry = AgencySettingChange.objects.get(kind=AgencySettingChange.Kind.TAX)
        self.assertEqual((entry.old_value["rate"], entry.new_value["rate"]), ("18.00", "10.00"))
        self.assertEqual(self.client.delete(f"/api/v1/taxes/{tax.pk}/").status_code, 405)


@override_settings(**FEDAPAY_SETTINGS)
class TicketPrintInfoTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)

    def fill_agency(self):
        AgencyProfile.objects.update_or_create(pk=1, defaults=TEST_AGENCY)

    def online_paid_ticket(self, **booking_fields):
        booking = make_booking(self.context, customer=self.context["client"], seats=1)
        Booking.objects.filter(pk=booking.pk).update(**booking_fields)
        self.client.force_authenticate(self.context["client"])
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="9001")):
            paid = self.client.post(
                f"/api/v1/client/bookings/{booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "9001"},
                format="json",
            )
        self.assertEqual(paid.status_code, 200, paid.data)
        return booking.tickets.get()

    def client_ticket_json(self, ticket):
        rows = self.client.get("/api/v1/client/tickets/").json()
        rows = rows["results"] if isinstance(rows, dict) else rows
        return next(row for row in rows if row["id"] == ticket.pk)

    def test_empty_agency_prints_nothing_invented_and_no_tax_breakdown(self):
        ticket = self.online_paid_ticket()
        info = self.client_ticket_json(ticket)["print_info"]
        self.assertEqual(info["title"], "Billet de transport")
        self.assertTrue(info["paid"])
        self.assertEqual((info["sale"], info["payment_mode"]), ("Vente en ligne", "Mobile Money"))
        self.assertEqual(set(info["agency"].values()), {""})
        self.assertIsNone(info["price_excl_tax"])
        self.assertEqual(info["tax_lines"], [])
        self.assertEqual(info["conditions"], "")

    def test_with_agency_ifu_the_breakdown_is_printed(self):
        self.fill_agency()
        ticket = self.online_paid_ticket(buyer_ifu="TEST-ACHETEUR")
        info = self.client_ticket_json(ticket)["print_info"]
        self.assertEqual(info["agency"]["legal_name"], "TEST Raison sociale")
        self.assertEqual((info["price_incl_tax"], info["price_excl_tax"]), (1000, 847))
        self.assertEqual(info["tax_lines"][0]["amount"], 153)
        self.assertEqual(info["buyer_ifu"], "TEST-ACHETEUR")

    def test_bank_accounts_are_never_exposed(self):
        self.fill_agency()
        ticket = self.online_paid_ticket()
        private = self.client.get("/api/v1/client/tickets/").content.decode()
        public = self.client.get(f"/api/v1/client/tickets/public/{ticket.reference}/").content.decode()
        for body in (private, public):
            self.assertNotIn("bank_accounts", body)
            self.assertNotIn("compte bancaire", body)
        self.assertEqual(json.loads(public)["print_info"]["agency"]["ifu"], "TEST-IFU-0000")

    def test_counter_sale_prints_seller_and_payment_mode(self):
        counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER, first_name="Agent", last_name="TEST")
        self.client.force_authenticate(counter)
        seat = self.context["trip"].seats.order_by("number").first()
        created = self.client.post(
            "/api/v1/tickets/", {"trip": self.context["trip"].pk, "seat": seat.pk, "passenger_name": "Awa"}, format="json"
        )
        self.assertEqual(created.status_code, 201, created.data)
        paid = self.client.post(
            f"/api/v1/tickets/{created.data['id']}/pay/", {"payment_method": self.context["payment_method"].pk}, format="json"
        )
        self.assertEqual(paid.status_code, 200, paid.data)
        info = paid.data["ticket"]["print_info"]
        self.assertEqual(info["sale"], "Vendeur : Agent TEST")
        self.assertEqual(info["payment_mode"], self.context["payment_method"].label)

    def test_unpaid_ticket_has_no_payment_line(self):
        booking = make_booking(self.context, customer=self.context["client"], seats=1)
        self.client.force_authenticate(self.context["client"])
        info = self.client_ticket_json(booking.tickets.get())["print_info"]
        self.assertFalse(info["paid"])
        self.assertEqual(info["payment_mode"], "")

    def test_boarding_place_only_when_filled(self):
        ticket = self.online_paid_ticket()
        self.assertEqual(self.client_ticket_json(ticket)["print_info"]["boarding_place"], "")
        self.context["origin"].address = "TEST gare"
        self.context["origin"].save()
        self.assertEqual(self.client_ticket_json(ticket)["print_info"]["boarding_place"], "TEST gare")


class BuyerIfuTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.client.force_authenticate(self.context["client"])
        self.seats = list(self.context["trip"].seats.order_by("number"))

    def book(self, seat, buyer_ifu):
        return self.client.post(
            "/api/v1/client/bookings/",
            {"trip": self.context["trip"].pk, "buyer_ifu": buyer_ifu, "passengers": [{"full_name": "Awa", "seat": seat.pk}]},
            format="json",
        )

    def test_optional_ifu_is_stored(self):
        self.assertEqual(self.book(self.seats[0], "").status_code, 201)
        response = self.book(self.seats[1], " TEST 123 ")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Booking.objects.get(pk=response.data["id"]).buyer_ifu, "TEST 123")

    def test_invalid_ifu_is_refused_clearly(self):
        response = self.book(self.seats[0], "<script>")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Booking.objects.exists())
        self.assertFalse(Ticket.objects.exists())
