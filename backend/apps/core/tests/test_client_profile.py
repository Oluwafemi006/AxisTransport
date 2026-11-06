"""Le client corrige lui-même ses informations depuis « Mon profil »."""
from rest_framework.test import APITestCase

from apps.core.models import AccountChange, User

ME = "/api/v1/auth/me/"


class ClientProfileTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="test_profil", password="TEST-Mdp-42", role=User.Role.CLIENT, first_name="TEST", phone="",
        )
        self.client.force_authenticate(self.user)

    def test_client_changes_name_phone_and_email_and_it_is_logged(self):
        response = self.client.patch(ME, {
            "first_name": " Awa ", "last_name": "TEST", "phone": "+229 01 97 00 00 12", "email": "awa.test@exemple.test",
        }, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.user.refresh_from_db()
        self.assertEqual((self.user.first_name, self.user.last_name, self.user.phone), ("Awa", "TEST", "+229 01 97 00 00 12"))
        change = AccountChange.objects.get(target=self.user)
        self.assertEqual(change.actor, self.user)
        self.assertIn("téléphone", change.detail)

    def test_nothing_changed_writes_no_log(self):
        self.assertEqual(self.client.patch(ME, {"first_name": "TEST"}, format="json").status_code, 200)
        self.assertFalse(AccountChange.objects.exists())

    def test_first_name_and_phone_cannot_be_emptied(self):
        self.assertEqual(self.client.patch(ME, {"first_name": "  "}, format="json").status_code, 400)
        self.assertEqual(self.client.patch(ME, {"phone": ""}, format="json").status_code, 400)

    def test_invalid_phone_is_refused(self):
        for phone in ("abc", "12", "01 97 00 00 12 34 56 78 9"):
            self.assertEqual(self.client.patch(ME, {"phone": phone}, format="json").status_code, 400, phone)

    def test_role_username_and_empty_body_are_refused(self):
        for body in ({"role": "ADMIN"}, {"username": "autre"}, {"is_active": False}, {}):
            self.assertEqual(self.client.patch(ME, body, format="json").status_code, 400, body)
        self.user.refresh_from_db()
        self.assertEqual((self.user.role, self.user.username), (User.Role.CLIENT, "test_profil"))

    def test_staff_cannot_use_it(self):
        staff = User.objects.create_user(username="test_ctrl", password="TEST-Mdp-42", role=User.Role.CONTROLLER)
        self.client.force_authenticate(staff)
        self.assertEqual(self.client.patch(ME, {"first_name": "TEST"}, format="json").status_code, 403)
