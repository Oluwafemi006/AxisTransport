from django.core.management.base import BaseCommand

from apps.core.services import release_expired_holds


class Command(BaseCommand):
    help = "Libère les sièges dont la réservation temporaire a expiré."

    def handle(self, *args, **options):
        count = release_expired_holds()
        self.stdout.write(self.style.SUCCESS(f"{count} réservation(s) temporaire(s) expirée(s)."))

