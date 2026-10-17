import getpass

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError

from apps.core.models import User


class Command(BaseCommand):
    help = (
        "Crée le compte ADMINISTRATEUR réel, sur place, de façon interactive : le mot de passe est saisi "
        "masqué (deux fois) et n'apparaît ni à l'écran, ni dans l'historique du shell, ni dans un fichier."
    )

    def handle(self, *args, **options):
        if not self.stdin_is_interactive():
            raise CommandError("Commande interactive : lancez-la avec « docker compose ... exec backend ... » (sans -T).")
        username = input("Identifiant de l'administrateur : ").strip()
        if not username:
            raise CommandError("Identifiant vide : aucun compte créé.")
        if User.objects.filter(username__iexact=username).exists():
            raise CommandError(f"Le compte « {username} » existe déjà : rien n'a été modifié.")
        email = input("E-mail (facultatif, Entrée pour passer) : ").strip()
        password = getpass.getpass("Mot de passe (saisie masquée) : ")
        if password != getpass.getpass("Mot de passe, encore une fois : "):
            raise CommandError("Les deux saisies diffèrent : aucun compte créé.")
        candidate = User(username=username, email=email, role=User.Role.ADMIN)
        try:
            validate_password(password, user=candidate)
        except ValidationError as exc:
            raise CommandError("Mot de passe refusé : " + " ".join(exc.messages)) from exc
        User.objects.create_superuser(username=username, email=email, password=password, role=User.Role.ADMIN)
        self.stdout.write(self.style.SUCCESS(f"Administrateur « {username} » créé."))

    @staticmethod
    def stdin_is_interactive():
        import sys

        return sys.stdin.isatty()
