from django.core.management.base import BaseCommand

from apps.core.views import LoginAccountThrottle


class Command(BaseCommand):
    help = "Débloque la connexion d'un identifiant (toutes adresses) bloqué après trop de tentatives échouées."

    def add_arguments(self, parser):
        parser.add_argument("username", help="Identifiant à débloquer (majuscules et espaces ignorés).")

    def handle(self, *args, username, **options):
        LoginAccountThrottle.unblock(username)
        self.stdout.write(f"Connexion débloquée pour « {username.strip()} ».")
