"""Un compte ADMIN ne se connecte pas dans l'application mobile (en-tête X-Axis-Client) ; les autres rôles ne changent pas."""
from django.core.cache import cache
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.models import User

LOGIN = "/api/v1/auth/token/"
REFRESH = "/api/v1/auth/token/refresh/"
PASSWORD = "TEST-mot-de-passe-42"
APP = {"HTTP_X_AXIS_CLIENT": "app-mobile"}


class AdminNotInAppTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.users = {
            role: User.objects.create_user(username=f"{role.lower()}-test", password=PASSWORD, role=role)
            for role in (User.Role.ADMIN, User.Role.CONTROLLER, User.Role.COUNTER, User.Role.CLIENT)
        }

    def login(self, role, **headers):
        return self.client.post(LOGIN, {"username": f"{role.lower()}-test", "password": PASSWORD}, format="json", **headers)

    def test_admin_refused_in_app_with_french_message(self):
        response = self.login(User.Role.ADMIN, **APP)
        self.assertEqual(response.status_code, 403)
        self.assertIn("administrateur", response.data["detail"])
        self.assertEqual(response.data["code"], "admin_not_allowed_in_app")
        self.assertNotIn("access", response.data)

    def test_admin_still_logs_in_on_the_website(self):
        self.assertEqual(self.login(User.Role.ADMIN).status_code, 200)

    def test_other_roles_unchanged_in_app(self):
        for role in (User.Role.CONTROLLER, User.Role.COUNTER, User.Role.CLIENT):
            with self.subTest(role=role):
                cache.clear()
                self.assertEqual(self.login(role, **APP).status_code, 200)

    def test_wrong_password_stays_a_401(self):
        response = self.client.post(LOGIN, {"username": "admin-test", "password": "faux-TEST"}, format="json", **APP)
        self.assertEqual(response.status_code, 401)

    def test_refresh_refused_for_admin_in_app_only(self):
        token = str(RefreshToken.for_user(self.users[User.Role.ADMIN]))
        refused = self.client.post(REFRESH, {"refresh": token}, format="json", **APP)
        self.assertEqual(refused.status_code, 403)
        self.assertIn("administrateur", refused.data["detail"])
        self.assertEqual(refused.data["code"], "admin_not_allowed_in_app")
        # Le jeton n'a pas été consommé : le site peut encore s'en servir.
        self.assertEqual(self.client.post(REFRESH, {"refresh": token}, format="json").status_code, 200)

    def test_refresh_unchanged_for_controller_in_app(self):
        token = str(RefreshToken.for_user(self.users[User.Role.CONTROLLER]))
        self.assertEqual(self.client.post(REFRESH, {"refresh": token}, format="json", **APP).status_code, 200)
