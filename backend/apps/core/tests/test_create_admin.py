from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from apps.core.models import User

COMMAND = "apps.core.management.commands.create_admin"


def run(answers, passwords, interactive=True):
    with (
        mock.patch(f"{COMMAND}.Command.stdin_is_interactive", return_value=interactive),
        mock.patch("builtins.input", side_effect=answers),
        mock.patch(f"{COMMAND}.getpass.getpass", side_effect=passwords),
    ):
        output = StringIO()
        call_command("create_admin", stdout=output)
        return output.getvalue()


class CreateAdminTests(TestCase):
    """Compte administrateur réel créé sur place, mot de passe saisi masqué : jamais en argument ni dans un fichier."""

    def test_creates_an_axis_admin(self):
        output = run(["chef", ""], ["Mot-De-Passe-Solide-2026", "Mot-De-Passe-Solide-2026"])
        user = User.objects.get(username="chef")
        self.assertEqual(user.role, User.Role.ADMIN)
        self.assertTrue(user.is_superuser and user.is_staff)
        self.assertTrue(user.check_password("Mot-De-Passe-Solide-2026"))
        self.assertNotIn("Mot-De-Passe", output)

    def test_mismatch_weak_existing_or_non_interactive_create_nothing(self):
        with self.assertRaisesMessage(CommandError, "diffèrent"):
            run(["chef", ""], ["Mot-De-Passe-Solide-2026", "autre"])
        with self.assertRaisesMessage(CommandError, "refusé"):
            run(["chef", ""], ["123", "123"])
        with self.assertRaisesMessage(CommandError, "interactive"):
            run([], [], interactive=False)
        self.assertFalse(User.objects.exists())
        User.objects.create_user(username="Chef", password="x")
        with self.assertRaisesMessage(CommandError, "existe déjà"):
            run(["chef"], [])
        self.assertEqual(User.objects.count(), 1)
