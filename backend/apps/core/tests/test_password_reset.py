"""Mot de passe oublié par lien (client), lien envoyé par l'admin, mot de passe provisoire du personnel."""
import re
from datetime import timedelta
from unittest.mock import patch

from django.core import mail
from django.core.cache import cache
from django.test import override_settings
from django.utils import timezone
from rest_framework.settings import api_settings
from rest_framework.test import APITestCase

from apps.core.models import AccountChange, PasswordAdminReset, PasswordResetLink, User

REQUEST = "/api/v1/auth/password-reset/request/"
OLD_CONFIRM = "/api/v1/auth/password-reset/confirm/"
LINK = "/api/v1/auth/password-reset/link/"
TOKEN = "/api/v1/auth/token/"
REFRESH = "/api/v1/auth/token/refresh/"
ME = "/api/v1/auth/me/"
CHANGE = "/api/v1/auth/password/change/"
NEW = "TEST-nouveau-Mdp-42"
OLD = "TEST-ancien-Mdp-42"
EMAIL = "client.test@exemple.test"
SITE = "https://site.test"


@override_settings(FRONTEND_URL=SITE)
class Base(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="test_client", email=EMAIL, password=OLD, role=User.Role.CLIENT)

    def ask(self, email=EMAIL, **extra):
        return self.client.post(REQUEST, {"email": email}, format="json", **extra)

    def token_from_mail(self):
        return re.search(r"/nouveau-mot-de-passe\?token=([\w-]+)", mail.outbox[-1].body).group(1)

    def use(self, token, password=NEW):
        return self.client.post(LINK, {"token": token, "password": password}, format="json")


class RequestTests(Base):
    def test_same_answer_whether_the_account_exists_or_not(self):
        known, unknown = self.ask(), self.ask("inconnu.test@exemple.test")
        self.assertEqual((known.status_code, known.json()), (unknown.status_code, unknown.json()))
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn(f"{SITE}/nouveau-mot-de-passe?token=", mail.outbox[0].body)
        self.assertNotIn("code", mail.outbox[0].body.lower().split("identifiant")[0].replace("unicode", ""))

    def test_token_is_stored_hashed_only(self):
        self.ask()
        token = self.token_from_mail()
        link = PasswordResetLink.objects.get()
        self.assertNotIn(token, link.token_hash)
        self.assertIsNone(link.created_by)
        self.assertTrue(link.email_sent)
        self.assertAlmostEqual(link.expires_at, timezone.now() + timedelta(hours=24), delta=timedelta(minutes=1))

    def test_staff_and_shared_address_get_nothing(self):
        User.objects.create_user(username="test_guichet", email="g.test@exemple.test", password=OLD, role=User.Role.COUNTER)
        self.ask("g.test@exemple.test")
        User.objects.create_user(username="test_client2", email=EMAIL, password=OLD, role=User.Role.CLIENT)
        self.ask()
        self.assertEqual(len(mail.outbox), 0)
        self.assertFalse(PasswordResetLink.objects.exists())

    def test_limit_per_address_and_per_ip(self):
        for _ in range(3):
            self.assertEqual(self.ask(REMOTE_ADDR="10.0.0.1").status_code, 200)
        self.assertEqual(self.ask(REMOTE_ADDR="10.0.0.2").status_code, 429)
        merged = {**api_settings.user_settings, "DEFAULT_THROTTLE_RATES": {**api_settings.DEFAULT_THROTTLE_RATES, "password_reset_address": "1/hour"}}
        with override_settings(REST_FRAMEWORK=merged):
            self.assertEqual(self.ask("a.test@exemple.test", REMOTE_ADDR="10.0.0.3").status_code, 200)
            self.assertEqual(self.ask("b.test@exemple.test", REMOTE_ADDR="10.0.0.3").status_code, 429)

    def test_old_code_screen_gets_a_clear_message(self):
        response = self.client.post(OLD_CONFIRM, {"email": EMAIL, "code": "123456", "password": NEW}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("lien", response.json()["detail"])


class LinkTests(Base):
    def test_link_changes_the_password_once_and_never_the_role(self):
        self.ask()
        token = self.token_from_mail()
        self.assertEqual(self.client.get(LINK, {"token": token}).status_code, 200)
        self.assertEqual(self.use(token).status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(NEW))
        self.assertEqual(self.user.role, User.Role.CLIENT)
        self.assertEqual(self.use(token, "TEST-autre-Mdp-42").status_code, 400)
        self.assertEqual(self.client.get(LINK, {"token": token}).status_code, 400)

    def test_expired_wrong_or_replaced_link_is_refused(self):
        self.ask()
        first = self.token_from_mail()
        self.ask()
        self.assertEqual(self.use(first).status_code, 400)
        second = self.token_from_mail()
        PasswordResetLink.objects.filter(used_at__isnull=True).update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.use(second).status_code, 400)
        self.assertEqual(self.use("TEST-jeton-faux").status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(OLD))

    def test_weak_password_does_not_use_the_link(self):
        self.ask()
        token = self.token_from_mail()
        self.assertEqual(self.use(token, "123").status_code, 400)
        self.assertEqual(self.use(token).status_code, 200)

    def test_link_closes_all_sessions(self):
        tokens = self.client.post(TOKEN, {"username": "test_client", "password": OLD}).json()
        self.ask()
        token = self.token_from_mail()
        with patch("django.utils.timezone.now", return_value=timezone.now() + timedelta(seconds=2)):
            self.assertEqual(self.use(token).status_code, 200)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        self.assertEqual(self.client.get(ME).status_code, 401)
        self.client.credentials()
        self.assertEqual(self.client.post(REFRESH, {"refresh": tokens["refresh"]}).status_code, 401)


class AdminLinkTests(Base):
    def setUp(self):
        super().setUp()
        self.admin = User.objects.create_user(username="test_admin", password=OLD, role=User.Role.ADMIN)
        self.client.force_authenticate(self.admin)

    def send(self, user=None):
        return self.client.post(f"/api/v1/users/{(user or self.user).pk}/reset-link/", {}, format="json")

    def test_admin_sends_a_link_by_email_and_it_is_logged(self):
        response = self.send()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual((response.data["email_sent"], response.data["link"]), (True, ""))
        self.assertEqual(PasswordResetLink.objects.get().created_by, self.admin)
        self.assertTrue(AccountChange.objects.filter(target=self.user, actor=self.admin, detail__contains="envoyé par e-mail").exists())
        self.client.force_authenticate(None)
        self.assertEqual(self.use(self.token_from_mail()).status_code, 200)

    def test_client_without_email_gets_a_link_to_copy(self):
        User.objects.filter(pk=self.user.pk).update(email="")
        response = self.send()
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data["email_sent"])
        self.assertTrue(response.data["link"].startswith(f"{SITE}/nouveau-mot-de-passe?token="))
        self.assertEqual(len(mail.outbox), 0)
        self.client.force_authenticate(None)
        self.assertEqual(self.use(response.data["link"].split("token=")[1]).status_code, 200)

    def test_failed_email_gives_a_link_to_copy(self):
        with patch("apps.core.password_reset.send_mail", side_effect=OSError("TEST smtp")):
            response = self.send()
        self.assertFalse(response.data["email_sent"])
        self.assertIn("token=", response.data["link"])

    @override_settings(FRONTEND_URL="", PUBLIC_WEB_URL="")
    def test_no_site_address_means_no_link_invented(self):
        response = self.send()
        self.assertEqual(response.status_code, 400)
        self.assertIn("PUBLIC_WEB_URL", response.data["detail"])

    def test_only_for_clients_and_only_by_an_admin(self):
        staff = User.objects.create_user(username="test_ctrl", password=OLD, role=User.Role.CONTROLLER)
        self.assertEqual(self.send(staff).status_code, 400)
        self.client.force_authenticate(staff)
        self.assertEqual(self.send().status_code, 403)

    def test_admin_can_no_longer_type_a_client_password(self):
        response = self.client.post(f"/api/v1/users/{self.user.pk}/reset-password/", {"password": NEW}, format="json")
        self.assertEqual(response.status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(OLD))


class ProvisionalPasswordTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.admin = User.objects.create_user(username="test_admin", password=OLD, role=User.Role.ADMIN)
        self.staff = User.objects.create_user(username="test_guichet", password=OLD, role=User.Role.COUNTER)

    def login(self, username, password):
        return self.client.post(TOKEN, {"username": username, "password": password}).json()

    def test_admin_reset_of_staff_is_provisional_and_logged(self):
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.post(f"/api/v1/users/{self.staff.pk}/reset-password/", {"password": NEW}).status_code, 200)
        self.staff.refresh_from_db()
        self.assertTrue(self.staff.must_change_password)
        self.assertEqual(PasswordAdminReset.objects.get().target, self.staff)

    def test_account_created_by_admin_with_a_password_is_provisional(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post("/api/v1/users/", {"username": "test_nouveau", "password": NEW, "role": "CONTROLLER"}, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(User.objects.get(username="test_nouveau").must_change_password)

    def test_everything_is_blocked_until_the_password_is_changed(self):
        User.objects.filter(pk=self.staff.pk).update(must_change_password=True)
        tokens = self.login("test_guichet", OLD)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        me = self.client.get(ME)
        self.assertEqual(me.status_code, 200)
        self.assertTrue(me.json()["must_change_password"])
        blocked = self.client.get("/api/v1/staff/sales/options/")
        self.assertEqual(blocked.status_code, 403)
        self.assertEqual(blocked.json()["detail"], "Choisissez un nouveau mot de passe avant de continuer.")
        self.assertEqual(self.client.patch(ME, {"email": "x.test@exemple.test"}, format="json").status_code, 403)
        changed = self.client.post(CHANGE, {"current_password": OLD, "new_password": NEW}, format="json")
        self.assertEqual(changed.status_code, 200, changed.data)
        self.staff.refresh_from_db()
        self.assertFalse(self.staff.must_change_password)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {changed.json()['access']}")
        self.assertEqual(self.client.get("/api/v1/staff/sales/options/").status_code, 200)

    def test_self_registration_is_not_provisional(self):
        response = self.client.post("/api/v1/auth/register/", {"username": "test_inscrit", "password": NEW}, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertFalse(User.objects.get(username="test_inscrit").must_change_password)
