from django.core.cache import cache
from django.test import override_settings
from rest_framework.settings import api_settings
from rest_framework.test import APITestCase

from apps.core.models import User

TOKEN = "/api/v1/auth/token/"
REGISTER = "/api/v1/auth/register/"


def rates(**values):
    """Seuils réduits pour les tests (mêmes mécanismes que les seuils réels)."""
    merged = {**api_settings.user_settings, "DEFAULT_THROTTLE_RATES": {**api_settings.DEFAULT_THROTTLE_RATES, **values}}
    return override_settings(REST_FRAMEWORK=merged)


class LoginThrottlingTests(APITestCase):
    def setUp(self):
        cache.clear()
        User.objects.create_user(username="awa", password="bon-mot-de-passe", role=User.Role.CLIENT)

    def login(self, username="awa", password="faux", **extra):
        return self.client.post(TOKEN, {"username": username, "password": password}, format="json", **extra)

    def test_normal_login_answer_is_unchanged(self):
        ok = self.login(password="bon-mot-de-passe")
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(set(ok.json()), {"access", "refresh"})
        wrong = self.login()
        self.assertEqual(wrong.status_code, 401)
        self.assertIn("detail", wrong.json())

    def test_account_is_blocked_temporarily_with_a_clear_message(self):
        with rates(login_account="3/hour", login_address="100/min"):
            for _ in range(3):
                self.assertEqual(self.login().status_code, 401)
            blocked = self.login(password="bon-mot-de-passe")  # même le bon mot de passe attend
            self.assertEqual(blocked.status_code, 429)
            self.assertRegex(blocked.json()["detail"], r"^Trop de tentatives, réessayez dans \d+ minutes?\.$")
            self.assertTrue(int(blocked["Retry-After"]) > 0)
            # Le blocage vise l'identifiant, quelle que soit l'adresse.
            self.assertEqual(self.login(REMOTE_ADDR="10.1.1.1").status_code, 429)
            # Un autre compte n'est pas touché.
            self.assertEqual(self.login(username="autre").status_code, 401)

    def test_identifier_is_matched_without_case_or_spaces(self):
        with rates(login_account="2/hour", login_address="100/min"):
            self.login(username="Awa")
            self.login(username=" awa ")
            self.assertEqual(self.login(username="AWA").status_code, 429)

    def test_successful_logins_never_count_nor_block(self):
        with rates(login_account="3/hour", login_address="100/min"):
            for _ in range(6):
                self.assertEqual(self.login(password="bon-mot-de-passe").status_code, 200)

    def test_success_resets_the_failure_count(self):
        with rates(login_account="3/hour", login_address="100/min"):
            self.login()
            self.login()
            self.assertEqual(self.login(password="bon-mot-de-passe").status_code, 200)
            self.login()
            self.login()
            self.assertEqual(self.login(password="bon-mot-de-passe").status_code, 200)

    def test_admin_can_unblock_an_account(self):
        from io import StringIO

        from django.core.management import call_command

        with rates(login_account="2/hour", login_address="100/min"):
            self.login()
            self.login()
            self.assertEqual(self.login(password="bon-mot-de-passe").status_code, 429)
            output = StringIO()
            call_command("unblock_login", " AWA ", stdout=output)
            self.assertIn("débloquée", output.getvalue())
            self.assertEqual(self.login(password="bon-mot-de-passe").status_code, 200)

    def test_block_is_temporary(self):
        with rates(login_account="2/min", login_address="100/min"):
            self.login()
            self.login()
            self.assertEqual(self.login().status_code, 429)
            cache.clear()  # équivaut à la fin de la fenêtre
            self.assertEqual(self.login(password="bon-mot-de-passe").status_code, 200)

    def test_address_is_blocked_across_identifiers(self):
        with rates(login_account="100/hour", login_address="3/min"):
            for name in ("a", "b", "c"):
                self.assertEqual(self.login(username=name).status_code, 401)
            self.assertEqual(self.login(username="d").status_code, 429)
            self.assertEqual(self.login(username="d", REMOTE_ADDR="10.9.9.9").status_code, 401)

    def test_behind_one_proxy_each_visitor_is_counted_separately(self):
        merged = {
            **api_settings.user_settings,
            "NUM_PROXIES": 1,
            "DEFAULT_THROTTLE_RATES": {**api_settings.DEFAULT_THROTTLE_RATES, "login_account": "100/hour", "login_address": "2/min"},
        }
        with override_settings(REST_FRAMEWORK=merged):
            # Toutes les requêtes arrivent du proxy (même REMOTE_ADDR) : seul X-Forwarded-For distingue les visiteurs.
            for name in ("a", "b"):
                self.login(username=name, HTTP_X_FORWARDED_FOR="203.0.113.7")
            self.assertEqual(self.login(username="c", HTTP_X_FORWARDED_FOR="203.0.113.7").status_code, 429)
            self.assertEqual(self.login(username="c", HTTP_X_FORWARDED_FOR="203.0.113.8").status_code, 401)

    def test_token_refresh_is_not_limited(self):
        refresh = self.login(password="bon-mot-de-passe").json()["refresh"]
        with rates(login_account="1/hour", login_address="1/min"):
            for _ in range(3):
                response = self.client.post(f"{TOKEN}refresh/", {"refresh": refresh}, format="json")
                self.assertEqual(response.status_code, 200)
                # Le serveur renouvelle le jeton de rafraîchissement : on utilise le nouveau.
                refresh = response.json().get("refresh", refresh)


class RegisterThrottlingTests(APITestCase):
    def setUp(self):
        cache.clear()

    def register(self, username, **extra):
        return self.client.post(REGISTER, {"username": username, "password": "Mot-de-passe-123"}, format="json", **extra)

    def test_signup_is_limited_per_address_with_a_clear_message(self):
        with rates(register_address="2/hour"):
            self.assertEqual(self.register("un").status_code, 201)
            self.assertEqual(self.register("deux").status_code, 201)
            blocked = self.register("trois")
            self.assertEqual(blocked.status_code, 429)
            self.assertIn("Trop de tentatives, réessayez dans", blocked.json()["detail"])
            self.assertEqual(self.register("trois", REMOTE_ADDR="10.2.2.2").status_code, 201)
        self.assertEqual(User.objects.filter(role=User.Role.CLIENT).count(), 3)

    def test_signup_still_creates_only_clients(self):
        response = self.client.post(REGISTER, {"username": "pirate", "password": "Mot-de-passe-123", "role": "ADMIN"}, format="json")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(User.objects.get(username="pirate").role, User.Role.CLIENT)
