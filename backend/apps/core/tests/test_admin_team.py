from unittest.mock import patch

from django.core import mail
from rest_framework.test import APITestCase

from apps.core.models import AccountChange, StaffInvitation, User

USERS = "/api/v1/users/"
INVITES = "/api/v1/staff-invitations/"
PASSWORD = "TEST-Mdp-solide-42"


class TeamTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username="test_admin", password=PASSWORD, role=User.Role.ADMIN)
        self.client.force_authenticate(self.admin)

    def create(self, username, role="COUNTER", **extra):
        return self.client.post(USERS, {"username": username, "password": PASSWORD, "role": role, **extra}, format="json")

    def test_creation_is_logged_and_staff_comes_before_clients(self):
        User.objects.create_user(username="a_client_test", password=PASSWORD, role=User.Role.CLIENT)
        self.assertEqual(self.create("z_guichet_test").status_code, 201)
        names = [row["username"] for row in self.client.get(USERS).json()["results"]]
        self.assertLess(names.index("z_guichet_test"), names.index("a_client_test"))
        self.assertTrue(AccountChange.objects.filter(action="CREATED", target__username="z_guichet_test", actor=self.admin).exists())

    def test_search_by_name_or_username(self):
        self.create("guichet_parakou_test", first_name="Stéphane")
        self.create("guichet_cotonou_test")
        rows = self.client.get(USERS, {"search": "stéph"}).json()["results"]
        self.assertEqual([row["username"] for row in rows], ["guichet_parakou_test"])

    def test_role_change_is_logged_and_closes_sessions(self):
        user = User.objects.get(pk=self.create("test_role").data["id"])
        response = self.client.patch(f"{USERS}{user.pk}/", {"role": "CONTROLLER"}, format="json")
        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertEqual(user.role, User.Role.CONTROLLER)
        self.assertIsNotNone(user.password_changed_at)
        self.assertTrue(AccountChange.objects.filter(action="ROLE", target=user).exists())

    def test_admin_cannot_change_own_role_or_deactivate_self(self):
        self.assertEqual(self.client.patch(f"{USERS}{self.admin.pk}/", {"role": "CLIENT"}, format="json").status_code, 400)
        self.assertEqual(self.client.post(f"{USERS}{self.admin.pk}/deactivate/").status_code, 400)

    def test_deactivation_blocks_login_and_is_reversible(self):
        user_id = self.create("test_desactive").data["id"]
        self.assertEqual(self.client.post(f"{USERS}{user_id}/deactivate/").status_code, 200)
        self.client.force_authenticate(None)
        login = self.client.post("/api/v1/auth/token/", {"username": "test_desactive", "password": PASSWORD})
        self.assertEqual(login.status_code, 401)
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.post(f"{USERS}{user_id}/activate/").status_code, 200)
        self.assertEqual(AccountChange.objects.filter(target_id=user_id).count(), 3)

    def test_only_an_admin_manages_the_team(self):
        counter = User.objects.create_user(username="test_g", password=PASSWORD, role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        self.assertEqual(self.client.get(USERS).status_code, 403)
        self.assertEqual(self.client.post(INVITES, {"email": "x.test@exemple.test", "role": "COUNTER"}).status_code, 403)

    def test_delete_is_not_offered(self):
        user_id = self.create("test_suppr").data["id"]
        self.assertEqual(self.client.delete(f"{USERS}{user_id}/").status_code, 405)


class InvitationTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username="test_admin", password=PASSWORD, role=User.Role.ADMIN)
        self.client.force_authenticate(self.admin)

    def invite(self, role="COUNTER", email="agent.test@exemple.test"):
        return self.client.post(INVITES, {"email": email, "first_name": "TEST Awa", "last_name": "TEST Bio", "role": role}, format="json")

    def test_invitation_is_emailed_with_names_and_copyable_link_for_counter(self):
        response = self.invite()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data["email_sent"])
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn("/activation?token=", response.data["activation_url"])
        self.assertEqual(self.client.get(INVITES).json()[0]["state"], "PENDING")

    def test_no_copyable_link_for_an_admin_invitation(self):
        self.assertIsNone(self.invite(role="ADMIN").data["activation_url"])

    def test_email_failure_is_reported_and_invitation_kept(self):
        with patch("apps.core.models.StaffInvitation.send_invitation_email", side_effect=OSError("smtp")):
            response = self.invite()
        self.assertEqual(response.status_code, 201)
        self.assertFalse(response.data["email_sent"])
        self.assertIn("n’a pas pu être envoyé", response.data["email_error"])
        self.assertEqual(StaffInvitation.objects.count(), 1)

    def test_resend_and_activation_copies_the_names(self):
        invitation_id = self.invite().data["id"]
        self.assertEqual(self.client.post(f"{INVITES}{invitation_id}/resend/").status_code, 200)
        invitation = StaffInvitation.objects.get(pk=invitation_id)
        self.client.force_authenticate(None)
        accepted = self.client.post("/api/v1/auth/invite/accept/", {"token": str(invitation.token), "password": PASSWORD}, format="json")
        self.assertIn(accepted.status_code, (200, 201), accepted.data)
        user = User.objects.get(email="agent.test@exemple.test")
        self.assertEqual((user.first_name, user.last_name, user.role), ("TEST Awa", "TEST Bio", User.Role.COUNTER))
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.get(INVITES).json()[0]["state"], "USED")

    def test_invalid_email_or_role_refused(self):
        self.assertEqual(self.invite(email="pas-un-email").status_code, 400)
        self.assertEqual(self.invite(role="CLIENT").status_code, 400)
