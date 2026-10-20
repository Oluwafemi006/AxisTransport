import uuid
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core import mail
from django.test import TestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from apps.core.models import StaffInvitation

User = get_user_model()


class StaffInvitationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.group_guichetier, _ = Group.objects.get_or_create(name="Guichetier")
        self.group_superviseur, _ = Group.objects.get_or_create(name="Superviseur")
        self.group_controleur, _ = Group.objects.get_or_create(name="Contrôleur")

        self.admin_user = User.objects.create_superuser(
            username="admin@axis.test",
            email="admin@axis.test",
            password="adminPassword123!",
            role=User.Role.ADMIN,
        )

    def test_send_invitation_email_content(self):
        """L'invitation envoie un e-mail avec le rôle, le lien d'activation et la mention du Play Store."""
        mail.outbox = []
        invitation = StaffInvitation.objects.create(
            email="agent.test@axis.test",
            group=self.group_guichetier,
            invited_by=self.admin_user,
        )
        invitation.send_invitation_email()

        self.assertEqual(len(mail.outbox), 1)
        email = mail.outbox[0]
        self.assertIn("agent.test@axis.test", email.to)
        self.assertIn("Guichetier", email.subject)
        self.assertIn("Guichetier", email.body)
        self.assertIn(f"/activation?token={invitation.token}", email.body)
        self.assertIn("Google Play Store", email.body)
        self.assertIn("com.axistransport.axis_transport_flutter", email.body)

    def test_verify_valid_token_get(self):
        """Un GET sur l'endpoint d'invitation confirme la validité et renvoie l'email et le groupe."""
        invitation = StaffInvitation.objects.create(
            email="agent.check@axis.test",
            group=self.group_controleur,
        )
        response = self.client.get(f"/api/auth/invite/accept/?token={invitation.token}")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["valid"])
        self.assertEqual(response.data["email"], "agent.check@axis.test")
        self.assertEqual(response.data["group"], "Contrôleur")

    def test_accept_invitation_success_guichetier(self):
        """L'acceptation d'une invitation Guichetier crée le compte avec le rôle COUNTER et le groupe."""
        invitation = StaffInvitation.objects.create(
            email="nouveau.guichet@axis.test",
            group=self.group_guichetier,
        )

        response = self.client.post(
            "/api/auth/invite/accept/",
            {"token": str(invitation.token), "password": "SecuredPassword2026!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])

        invitation.refresh_from_db()
        self.assertTrue(invitation.is_used)

        user = User.objects.get(email="nouveau.guichet@axis.test")
        self.assertTrue(user.is_active)
        self.assertTrue(user.is_staff)
        self.assertEqual(user.role, User.Role.COUNTER)
        self.assertTrue(user.groups.filter(name="Guichetier").exists())
        self.assertTrue(user.check_password("SecuredPassword2026!"))

    def test_accept_invitation_success_superviseur(self):
        """L'acceptation d'une invitation Superviseur crée le compte avec le rôle ADMIN et le groupe."""
        invitation = StaffInvitation.objects.create(
            email="nouveau.superviseur@axis.test",
            group=self.group_superviseur,
        )

        response = self.client.post(
            "/api/v1/auth/invite/accept/",
            {"token": str(invitation.token), "password": "SuperPassword2026!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        user = User.objects.get(email="nouveau.superviseur@axis.test")
        self.assertEqual(user.role, User.Role.ADMIN)
        self.assertTrue(user.groups.filter(name="Superviseur").exists())

    def test_accept_invitation_expired_fails(self):
        """Une invitation expirée (J > 2) est refusée."""
        invitation = StaffInvitation.objects.create(
            email="expire@axis.test",
            group=self.group_controleur,
            expires_at=timezone.now() - timedelta(hours=1),
        )

        response = self.client.post(
            "/api/auth/invite/accept/",
            {"token": str(invitation.token), "password": "SecuredPassword2026!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("expiré", response.data["error"].lower())

    def test_accept_invitation_already_used_fails(self):
        """Une invitation déjà utilisée ne peut pas être réutilisée."""
        invitation = StaffInvitation.objects.create(
            email="used@axis.test",
            group=self.group_guichetier,
            is_used=True,
        )

        response = self.client.post(
            "/api/auth/invite/accept/",
            {"token": str(invitation.token), "password": "SecuredPassword2026!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("déjà été utilisée", response.data["error"])

    def test_accept_invitation_invalid_token_fails(self):
        """Un token inconnu retourne 404."""
        response = self.client.post(
            "/api/auth/invite/accept/",
            {"token": str(uuid.uuid4()), "password": "SecuredPassword2026!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

