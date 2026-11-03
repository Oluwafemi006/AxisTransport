import time

from django.core.cache import cache
from rest_framework.test import APITestCase

from apps.core.models import User

ME = "/api/v1/auth/me/"
CHANGE = "/api/v1/auth/password/change/"
TOKEN = "/api/v1/auth/token/"
REFRESH = "/api/v1/auth/token/refresh/"
OLD = "TEST-ancien-Mdp-42"
NEW = "TEST-nouveau-Mdp-42"


class EmailTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="test_client", password=OLD, role=User.Role.CLIENT)

    def test_client_adds_an_email(self):
        self.client.force_authenticate(self.user)
        response = self.client.patch(ME, {"email": "client.test@exemple.test"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "client.test@exemple.test")

    def test_invalid_email_is_refused(self):
        self.client.force_authenticate(self.user)
        self.assertEqual(self.client.patch(ME, {"email": "pas-un-email"}, format="json").status_code, 400)

    def test_only_the_email_can_be_changed(self):
        self.client.force_authenticate(self.user)
        self.assertEqual(self.client.patch(ME, {"role": "ADMIN"}, format="json").status_code, 400)
        self.user.refresh_from_db()
        self.assertEqual(self.user.role, User.Role.CLIENT)

    def test_staff_cannot_change_it_here(self):
        staff = User.objects.create_user(username="test_guichet", password=OLD, role=User.Role.COUNTER)
        self.client.force_authenticate(staff)
        self.assertEqual(self.client.patch(ME, {"email": "g.test@exemple.test"}, format="json").status_code, 403)


class PasswordChangeTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="test_client", password=OLD, role=User.Role.CLIENT)
        self.tokens = self.client.post(TOKEN, {"username": "test_client", "password": OLD}).json()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")

    def change(self, current=OLD, new=NEW):
        return self.client.post(CHANGE, {"current_password": current, "new_password": new}, format="json")

    def test_wrong_current_password_is_refused(self):
        response = self.change(current="faux")
        self.assertEqual(response.status_code, 400)
        self.assertIn("current_password", response.json())
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(OLD))

    def test_weak_new_password_is_refused(self):
        self.assertEqual(self.change(new="123").status_code, 400)

    def test_change_closes_other_sessions_and_keeps_this_one(self):
        # Jetons datés à la seconde : on attend que la session existante soit strictement plus ancienne.
        time.sleep(1.1)
        response = self.change()
        self.assertEqual(response.status_code, 200)
        fresh = response.json()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")
        self.assertEqual(self.client.get(ME).status_code, 401)
        self.client.credentials()
        self.assertEqual(self.client.post(REFRESH, {"refresh": self.tokens["refresh"]}).status_code, 401)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {fresh['access']}")
        self.assertEqual(self.client.get(ME).status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(NEW))

    def test_attempts_are_limited(self):
        for _ in range(10):
            self.change(current="faux")
        self.assertEqual(self.change().status_code, 429)

    def test_login_required(self):
        self.client.credentials()
        self.assertEqual(self.change().status_code, 401)
