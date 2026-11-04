from unittest import mock

from django.test import override_settings
from rest_framework.test import APITestCase

from apps.core.models import Location, Parcel, PaymentMethod, Transaction, User
from apps.core.payments import VerifiedPayment


class ParcelPaymentTests(APITestCase):
    def setUp(self):
        self.parakou = Location.objects.create(name="Parakou", active=True)
        self.cotonou = Location.objects.create(name="Cotonou", active=True)
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)
        self.momo = PaymentMethod.objects.create(code="FEDAPAY", label="Mobile Money", active=True)
        self.counter = User.objects.create_user(username="test_guichet_c", password="s", role=User.Role.COUNTER)
        self.parcel = Parcel.objects.create(
            sender_name="TEST Exp", sender_phone="90000000", recipient_name="TEST Dest", recipient_phone="90000001",
            origin=self.parakou, destination=self.cotonou, description="TEST carton", amount=2000,
        )
        self.client.force_authenticate(self.counter)

    def pay(self, method):
        return self.client.post(f"/api/v1/parcels/{self.parcel.pk}/pay/", {"payment_method": method.pk}, format="json")

    def test_cash_payment_issues_a_paid_ticket_once(self):
        response = self.pay(self.cash)
        self.assertEqual(response.status_code, 200, response.data)
        receipt = response.data["receipt"]
        self.assertEqual((receipt["paid"], receipt["amount"], receipt["payment_mode"]), (True, 2000, "Espèces"))
        self.assertEqual((receipt["origin"], receipt["destination"]), ("Parakou", "Cotonou"))
        self.assertEqual(self.pay(self.cash).status_code, 400)  # déjà payé
        self.assertEqual(Transaction.objects.filter(parcel=self.parcel, status="SUCCEEDED").count(), 1)

    def test_no_payment_before_the_agency_sets_a_price(self):
        Parcel.objects.filter(pk=self.parcel.pk).update(amount=None)
        response = self.pay(self.cash)
        self.assertEqual(response.status_code, 400)
        self.assertIn("prix", str(response.data))

    def test_controller_can_collect_but_a_client_cannot(self):
        controller = User.objects.create_user(username="test_ctrl_c", password="s", role=User.Role.CONTROLLER)
        client = User.objects.create_user(username="test_client_c", password="s", role=User.Role.CLIENT)
        self.parcel.customer = client
        self.parcel.save(update_fields=["customer"])
        self.client.force_authenticate(client)
        self.assertEqual(self.pay(self.cash).status_code, 403)
        self.assertEqual(self.client.get(f"/api/v1/parcels/{self.parcel.pk}/receipt/").status_code, 403)
        self.client.force_authenticate(controller)
        self.assertEqual(self.pay(self.cash).status_code, 200)

    @override_settings(FEDAPAY_SECRET_KEY="TEST-cle")
    def test_mobile_money_is_paid_only_after_verified_approval(self):
        with mock.patch("apps.core.payments._fedapay_create_transaction", return_value={"id": 4242, "payment_url": "https://pay.test.invalid/4242"}):
            started = self.pay(self.momo)
        self.assertEqual(started.status_code, 200, started.data)
        self.assertEqual(started.data["checkout"]["payment_url"], "https://pay.test.invalid/4242")
        self.assertFalse(started.data["receipt"]["paid"])
        good = VerifiedPayment(provider="FEDAPAY", external_id="4242", amount=2000, currency="XOF", metadata={"parcel_id": self.parcel.pk})
        with mock.patch("apps.core.payments.verify_fedapay_transaction", return_value=good):
            verified = self.client.post(f"/api/v1/parcels/{self.parcel.pk}/verify/")
        self.assertEqual(verified.status_code, 200, verified.data)
        self.assertTrue(verified.data["receipt"]["paid"])

    @override_settings(FEDAPAY_SECRET_KEY="TEST-cle")
    def test_mobile_money_for_another_parcel_or_amount_is_refused(self):
        with mock.patch("apps.core.payments._fedapay_create_transaction", return_value={"id": 4243, "payment_url": "https://pay.test.invalid/4243"}):
            self.pay(self.momo)
        for proof in (
            VerifiedPayment(provider="FEDAPAY", external_id="4243", amount=2000, currency="XOF", metadata={"parcel_id": 999}),
            VerifiedPayment(provider="FEDAPAY", external_id="4243", amount=500, currency="XOF", metadata={"parcel_id": self.parcel.pk}),
        ):
            with mock.patch("apps.core.payments.verify_fedapay_transaction", return_value=proof):
                self.assertEqual(self.client.post(f"/api/v1/parcels/{self.parcel.pk}/verify/").status_code, 400)
        self.assertFalse(Transaction.objects.filter(parcel=self.parcel, status="SUCCEEDED").exists())
