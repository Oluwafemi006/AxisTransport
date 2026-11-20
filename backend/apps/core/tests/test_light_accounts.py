"""Comptes allégés : téléphone comme identifiant, e-mail vérifié, recherche de billet au guichet. Numéros fictifs."""
from django.core import mail
from django.core.cache import cache
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from apps.core.models import User
from apps.core.phone import normalize_benin_phone

from .factories import build_operational_context
from .test_payment_security import make_booking

REGISTER = "/api/v1/auth/register/"
LOGIN = "/api/v1/auth/token/"
ME = "/api/v1/auth/me/"
SEND = "/api/v1/auth/email/send-code/"
VERIFY = "/api/v1/auth/email/verify/"
RESET = "/api/v1/auth/password-reset/request/"
SEARCH = "/api/v1/tickets/counter-search/"
PASSWORD = "TEST-mot-de-passe-42"


class NormalizeTests(SimpleTestCase):
    def test_common_benin_formats_give_one_form(self):
        for raw in ("0100000009", "01 00 00 00 09", "01.00.00.00.09", "01-00-00-00-09", "+229 01 00 00 00 09",
                    "+2290100000009", "00229 0100000009", "229 01 00 00 00 09"):
            with self.subTest(raw=raw):
                self.assertEqual(normalize_benin_phone(raw), "+2290100000009")

    def test_other_numbers_are_refused(self):
        for raw in ("", "TEST", "97000009", "0200000009", "+33600000009", "010000000", "01000000099"):
            with self.subTest(raw=raw):
                self.assertIsNone(normalize_benin_phone(raw))


class RegisterAndLoginTests(APITestCase):
    def setUp(self):
        cache.clear()

    def test_phone_and_password_are_enough(self):
        response = self.client.post(REGISTER, {"phone": "01 00 00 00 09", "password": PASSWORD}, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        user = User.objects.get()
        self.assertEqual((user.username, user.phone, user.role, user.email), ("+2290100000009", "+2290100000009", User.Role.CLIENT, ""))
        self.assertFalse(user.email_verified)

    def test_role_cannot_be_chosen_and_duplicate_phone_is_refused(self):
        self.client.post(REGISTER, {"phone": "0100000009", "password": PASSWORD, "role": "ADMIN"}, format="json")
        self.assertEqual(User.objects.get().role, User.Role.CLIENT)
        again = self.client.post(REGISTER, {"phone": "+229 01.00.00.00.09", "password": PASSWORD}, format="json")
        self.assertEqual(again.status_code, 400)
        self.assertIn("existe déjà", str(again.data))

    def test_old_account_with_formatted_phone_blocks_a_duplicate(self):
        User.objects.create_user(username="ancien-test", password=PASSWORD, phone="01 00 00 00 09")
        response = self.client.post(REGISTER, {"phone": "0100000009", "password": PASSWORD}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_invalid_phone_is_refused_in_french(self):
        response = self.client.post(REGISTER, {"phone": "TEST", "password": PASSWORD}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("01", str(response.data["phone"]))

    def test_login_with_any_format_of_the_phone(self):
        self.client.post(REGISTER, {"phone": "0100000009", "password": PASSWORD}, format="json")
        for login in ("0100000009", "01 00 00 00 09", "+229 01 00 00 00 09"):
            with self.subTest(login=login):
                cache.clear()
                self.assertEqual(self.client.post(LOGIN, {"username": login, "password": PASSWORD}).status_code, 200)

    def test_existing_usernames_still_log_in_exactly(self):
        """Comptes existants (dont ceux de test du Play Store) : l'identifiant exact passe d'abord, sans changement."""
        User.objects.create_user(username="demo.test", password=PASSWORD, phone="0100000008")
        self.assertEqual(self.client.post(LOGIN, {"username": "demo.test", "password": PASSWORD}).status_code, 200)
        # Et par son téléphone enregistré dans un ancien format.
        self.assertEqual(self.client.post(LOGIN, {"username": "01 00 00 00 08", "password": PASSWORD}).status_code, 200)
        self.assertEqual(User.objects.get().username, "demo.test")

    def test_phone_shared_by_two_old_accounts_logs_none_in_by_phone(self):
        User.objects.create_user(username="double-a-test", password=PASSWORD, phone="0100000007")
        User.objects.create_user(username="double-b-test", password=PASSWORD, phone="01 00 00 00 07")
        self.assertEqual(self.client.post(LOGIN, {"username": "0100000007", "password": PASSWORD}).status_code, 401)


class EmailVerificationTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="+2290100000009", phone="+2290100000009", password=PASSWORD, first_name="Client TEST")
        self.client.force_authenticate(self.user)

    def code_from_mail(self):
        body = mail.outbox[-1].body
        return next(word for word in body.split() if word.isdigit() and len(word) == 6)

    def test_add_email_send_code_and_verify(self):
        self.assertEqual(self.client.patch(ME, {"email": "Client.Test@Exemple.test"}, format="json").status_code, 200)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "client.test@exemple.test")
        self.assertFalse(self.user.email_verified)
        sent = self.client.post(SEND)
        self.assertEqual(sent.status_code, 200, sent.data)
        self.assertEqual(self.client.post(VERIFY, {"code": "000000" if self.code_from_mail() != "000000" else "111111"}).status_code, 400)
        verified = self.client.post(VERIFY, {"code": self.code_from_mail()})
        self.assertEqual(verified.status_code, 200, verified.data)
        self.assertTrue(verified.data["user"]["email_verified"])

    def test_changing_the_email_needs_a_new_verification(self):
        User.objects.filter(pk=self.user.pk).update(email="a.test@exemple.test", email_verified=True)
        self.client.patch(ME, {"email": "b.test@exemple.test"}, format="json")
        self.user.refresh_from_db()
        self.assertFalse(self.user.email_verified)

    def test_name_is_optional_later(self):
        self.assertEqual(self.client.patch(ME, {"last_name": "Nom TEST"}, format="json").status_code, 200)

    def test_no_email_no_code(self):
        response = self.client.post(SEND)
        self.assertEqual(response.status_code, 503)
        self.assertIn("Ajoutez", response.data["detail"])

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend", EMAIL_HOST="", DEFAULT_FROM_EMAIL="")
    def test_smtp_not_configured_says_so_without_500(self):
        User.objects.filter(pk=self.user.pk).update(email="c.test@exemple.test")
        self.user.refresh_from_db()
        self.client.force_authenticate(self.user)
        response = self.client.post(SEND)
        self.assertEqual(response.status_code, 503)
        self.assertIn("pas encore disponible", response.data["detail"])
        self.assertFalse(response.data["email_sent"])

    def test_sending_failure_is_not_reported_as_sent(self):
        from unittest import mock

        User.objects.filter(pk=self.user.pk).update(email="d.test@exemple.test")
        self.user.refresh_from_db()
        self.client.force_authenticate(self.user)
        with mock.patch("apps.core.email_verification.send_mail", side_effect=OSError("TEST")):
            response = self.client.post(SEND)
        self.assertEqual(response.status_code, 503)
        self.assertIn("n'a pas pu être envoyé", response.data["detail"])

    @override_settings(PUBLIC_WEB_URL="https://site.exemple.test")
    def test_password_reset_only_for_a_verified_email(self):
        User.objects.filter(pk=self.user.pk).update(email="e.test@exemple.test")
        self.client.force_authenticate(None)
        self.client.post(RESET, {"email": "e.test@exemple.test"}, format="json")
        self.assertEqual(len(mail.outbox), 0)
        User.objects.filter(pk=self.user.pk).update(email_verified=True)
        cache.clear()
        self.client.post(RESET, {"email": "e.test@exemple.test"}, format="json")
        self.assertEqual(len(mail.outbox), 1)


class CounterTicketSearchTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.context = build_operational_context()
        self.booking = make_booking(self.context, customer=self.context["client"], seats=1)
        self.ticket = self.booking.tickets.get()
        self.ticket.passenger_name = "Passager TEST"
        self.ticket.passenger_phone = "01 00 00 00 09"
        self.ticket.save(update_fields=["passenger_name", "passenger_phone"])
        self.counter = User.objects.create_user(username="guichet-recherche-test", password=PASSWORD, role=User.Role.COUNTER)
        self.client.force_authenticate(self.counter)

    def search(self, query):
        return self.client.get(SEARCH, {"q": query})

    def test_by_reference_full_phone_or_six_digits(self):
        for query in (self.ticket.reference.lower(), "+229 01 00 00 00 09", "0100000009", "000009"):
            with self.subTest(query=query):
                response = self.search(query)
                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual([row["reference"] for row in response.data], [self.ticket.reference])

    def test_no_search_by_name_or_too_few_digits(self):
        for query in ("Passager TEST", "00009", ""):
            with self.subTest(query=query):
                self.assertEqual(self.search(query).status_code, 400)

    def test_client_and_controller_cannot_search(self):
        for user in (self.context["client"], self.context["controller"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.search("0100000009").status_code, 403)

    def test_searches_are_limited_per_agent(self):
        from unittest import mock

        from apps.core import views

        with mock.patch.object(views.CounterTicketSearchThrottle, "THROTTLE_RATES", {"counter_ticket_search": "2/hour"}):
            codes = [self.search("0100000009").status_code for _ in range(3)]
        self.assertEqual(codes, [200, 200, 429])

    def test_counter_cannot_cancel(self):
        response = self.client.post(f"/api/v1/tickets/{self.ticket.pk}/transition/", {"status": "CANCELLED"}, format="json")
        self.assertEqual(response.status_code, 403)
