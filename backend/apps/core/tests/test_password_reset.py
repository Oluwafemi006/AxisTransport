import re
from datetime import timedelta
from unittest.mock import patch

from django.core import mail
from django.core.cache import cache
from django.test import override_settings
from django.utils import timezone
from rest_framework.settings import api_settings
from rest_framework.test import APITestCase

from apps.core.models import PasswordAdminReset, PasswordResetCode, User

REQUEST = "/api/v1/auth/password-reset/request/"
CONFIRM = "/api/v1/auth/password-reset/confirm/"
TOKEN = "/api/v1/auth/token/"
REFRESH = "/api/v1/auth/token/refresh/"
ME = "/api/v1/auth/me/"
NEW = "TEST-nouveau-Mdp-42"
OLD = "TEST-ancien-Mdp-42"
EMAIL = "client.test@exemple.test"


class Base(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="test_client", email=EMAIL, password=OLD, role=User.Role.CLIENT)

    def ask(self, email=EMAIL, **extra):
        return self.client.post(REQUEST, {"email": email}, format="json", **extra)

    def code(self):
        return re.search(r"\b(\d{6})\b", mail.outbox[-1].body).group(1)

    def confirm(self, code, password=NEW, email=EMAIL):
        return self.client.post(CONFIRM, {"email": email, "code": code, "password": password}, format="json")

    def wrong(self, code):
        return "000000" if code != "000000" else "111111"


class RequestTests(Base):
    def test_same_answer_whether_the_account_exists_or_not(self):
        known = self.ask()
        unknown = self.ask("inconnu.test@exemple.test")
        self.assertEqual((known.status_code, known.json()), (unknown.status_code, unknown.json()))
        self.assertEqual(len(mail.outbox), 1)

    def test_code_is_stored_hashed(self):
        self.ask()
        self.assertNotIn(self.code(), PasswordResetCode.objects.get().code_hash)
        self.assertLessEqual(PasswordResetCode.objects.get().expires_at, timezone.now() + timedelta(minutes=15))

    def test_staff_gets_no_code(self):
        for role in (User.Role.COUNTER, User.Role.CONTROLLER, User.Role.ADMIN):
            User.objects.create_user(username=f"test_{role}", email=f"{role}.test@exemple.test", password=OLD, role=role)
            self.assertEqual(self.ask(f"{role}.test@exemple.test").status_code, 200)
        self.assertEqual(mail.outbox, [])

    def test_shared_address_gets_no_code(self):
        User.objects.create_user(username="test_double", email=EMAIL, password=OLD, role=User.Role.CLIENT)
        self.assertEqual(self.ask().status_code, 200)
        self.assertEqual(mail.outbox, [])

    def test_limit_per_address_and_per_ip(self):
        for _ in range(3):
            self.assertEqual(self.ask(REMOTE_ADDR="10.0.0.1").status_code, 200)
        self.assertEqual(self.ask(REMOTE_ADDR="10.0.0.2").status_code, 429)
        self.assertEqual(self.ask("inconnu.test@exemple.test", REMOTE_ADDR="10.0.0.2").status_code, 200)
        merged = {
            **api_settings.user_settings,
            "DEFAULT_THROTTLE_RATES": {**api_settings.DEFAULT_THROTTLE_RATES, "password_reset_address": "1/hour"},
        }
        with override_settings(REST_FRAMEWORK=merged):
            self.assertEqual(self.ask("a.test@exemple.test", REMOTE_ADDR="10.0.0.3").status_code, 200)
            self.assertEqual(self.ask("b.test@exemple.test", REMOTE_ADDR="10.0.0.3").status_code, 429)


class ConfirmTests(Base):
    def test_good_code_changes_the_password_once(self):
        self.ask()
        code = self.code()
        self.assertEqual(self.confirm(code).status_code, 200)
        self.assertEqual(self.client.post(TOKEN, {"username": "test_client", "password": NEW}).status_code, 200)
        self.assertEqual(self.confirm(code, "TEST-autre-Mdp-43").status_code, 400)

    def test_expired_code_is_refused(self):
        self.ask()
        PasswordResetCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.confirm(self.code()).status_code, 400)

    def test_five_attempts_at_most(self):
        self.ask()
        code = self.code()
        for _ in range(5):
            self.assertEqual(self.confirm(self.wrong(code)).status_code, 400)
        self.assertEqual(self.confirm(code).status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(OLD))

    def test_new_request_cancels_the_previous_code(self):
        self.ask()
        first = self.code()
        self.ask()
        if first != self.code():
            self.assertEqual(self.confirm(first).status_code, 400)
        self.assertEqual(self.confirm(self.code()).status_code, 200)

    def test_same_refusal_for_unknown_address(self):
        self.ask()
        known = self.confirm(self.wrong(self.code()))
        unknown = self.confirm("123456", email="inconnu.test@exemple.test")
        self.assertEqual((known.status_code, known.json()), (unknown.status_code, unknown.json()))

    def test_weak_password_does_not_consume_an_attempt(self):
        self.ask()
        self.assertEqual(self.confirm(self.code(), "123").status_code, 400)
        self.assertEqual(PasswordResetCode.objects.get().attempts, 0)
        self.assertIsNone(PasswordResetCode.objects.get().used_at)


class SessionTests(Base):
    def login(self):
        return self.client.post(TOKEN, {"username": "test_client", "password": OLD}).json()

    def assert_closed(self, tokens):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        self.assertEqual(self.client.get(ME).status_code, 401)
        self.client.credentials()
        self.assertEqual(self.client.post(REFRESH, {"refresh": tokens["refresh"]}).status_code, 401)

    def past(self):
        # Les jetons sont datés à la seconde : on les vieillit plutôt que d'attendre.
        return patch("django.utils.timezone.now", return_value=timezone.now() + timedelta(seconds=2))

    def test_reset_closes_sessions_including_renewed_tokens(self):
        first = self.login()
        renewed = self.client.post(REFRESH, {"refresh": first["refresh"]}).json()
        self.ask()
        code = self.code()
        with self.past():
            self.assertEqual(self.confirm(code).status_code, 200)
        self.assert_closed({"access": first["access"], "refresh": renewed["refresh"]})


class AdminResetTests(Base):
    def setUp(self):
        super().setUp()
        self.admin = User.objects.create_user(username="test_admin", password=OLD, role=User.Role.ADMIN)
        self.url = f"/api/v1/users/{self.user.pk}/reset-password/"

    def test_admin_resets_a_client_without_email_and_it_is_logged(self):
        User.objects.filter(pk=self.user.pk).update(email="")
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.post(self.url, {"password": NEW}).status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(NEW))
        self.assertIsNotNone(self.user.password_changed_at)
        entry = PasswordAdminReset.objects.get()
        self.assertEqual((entry.target, entry.actor), (self.user, self.admin))

    def test_only_an_admin_can_do_it(self):
        counter = User.objects.create_user(username="test_guichet", password=OLD, role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        self.assertEqual(self.client.post(self.url, {"password": NEW}).status_code, 403)

    def test_weak_password_is_refused(self):
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.post(self.url, {"password": "123"}).status_code, 400)
