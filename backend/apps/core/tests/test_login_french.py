"""Connexion refusée : le message de SimpleJWT est servi en français (catalogue chargé par INSTALLED_APPS)."""
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase


class LoginFrenchMessageTests(APITestCase):
    def test_wrong_password_message_is_french(self):
        get_user_model().objects.create_user(username="agent-test", password="TEST-pass-123")
        response = self.client.post("/api/v1/auth/token/", {"username": "agent-test", "password": "faux-TEST"}, format="json")
        self.assertEqual(response.status_code, 401, response.content)
        text = response.content.decode()
        self.assertIn("Aucun compte actif", text)
        self.assertNotIn("No active account", text)
