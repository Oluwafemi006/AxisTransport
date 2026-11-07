"""Invitation du personnel : un compte client n'est jamais repris ; un membre existant voit ses sessions fermées."""
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth.models import Group
from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import StaffInvitation, User

ACCEPT = "/api/v1/auth/invite/accept/"
NEW = "TEST-nouveau-Mdp-42"
OLD = "TEST-ancien-Mdp-42"


class InvitationTakeoverTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.group, _ = Group.objects.get_or_create(name="Contrôleur")
        self.admin = User.objects.create_user(username="test_admin", password=OLD, role=User.Role.ADMIN)

    def invite(self, email):
        return StaffInvitation.objects.create(email=email, group=self.group, invited_by=self.admin)

    def test_client_account_is_never_turned_into_staff(self):
        client = User.objects.create_user(username="test_client", email="client.test@exemple.test", password=OLD, role=User.Role.CLIENT)
        invitation = self.invite("CLIENT.test@exemple.test")
        response = self.client.post(ACCEPT, {"token": str(invitation.token), "password": NEW}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("compte client", response.json()["error"])
        client.refresh_from_db()
        self.assertEqual(client.role, User.Role.CLIENT)
        self.assertTrue(client.check_password(OLD))
        invitation.refresh_from_db()
        self.assertFalse(invitation.is_used)

    def test_admin_cannot_invite_a_client_address(self):
        User.objects.create_user(username="test_client", email="client.test@exemple.test", password=OLD, role=User.Role.CLIENT)
        self.client.force_authenticate(self.admin)
        response = self.client.post("/api/v1/staff-invitations/", {"email": "client.test@exemple.test", "role": "CONTROLLER"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("compte client", str(response.data))

    def test_existing_staff_account_gets_its_sessions_closed(self):
        User.objects.create_user(username="ancien.test@exemple.test", email="ancien.test@exemple.test", password=OLD, role=User.Role.COUNTER, is_active=False)
        User.objects.filter(username="ancien.test@exemple.test").update(is_active=True)
        tokens = self.client.post("/api/v1/auth/token/", {"username": "ancien.test@exemple.test", "password": OLD}).json()
        invitation = self.invite("ancien.test@exemple.test")
        with patch("django.utils.timezone.now", return_value=timezone.now() + timedelta(seconds=2)):
            response = self.client.post(ACCEPT, {"token": str(invitation.token), "password": NEW}, format="json")
        self.assertEqual(response.status_code, 200, response.json())
        member = User.objects.get(username="ancien.test@exemple.test")
        self.assertEqual(member.role, User.Role.CONTROLLER)
        self.assertTrue(member.check_password(NEW))
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 401)
