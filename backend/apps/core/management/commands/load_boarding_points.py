from django.core.management.base import BaseCommand
from django.db import transaction

from apps.core.models import BoardingPoint, Location


class Command(BaseCommand):
    help = (
        "Crée de façon idempotente le point d'embarquement « Parc ALBARIKA » à Parakou "
        "uniquement si Parakou n'a encore aucun point d'arrêt (actif ou non). "
        "Ne crée aucun point pour Porto-Novo ni pour les autres villes."
    )

    @transaction.atomic
    def handle(self, *args, **options):
        parakou, _ = Location.objects.get_or_create(name="Parakou")
        if BoardingPoint.objects.filter(location=parakou).exists():
            self.stdout.write("Parakou possède déjà au moins un point d'embarquement (inchangé).")
            return
        point = BoardingPoint.objects.create(
            location=parakou,
            name="Parc ALBARIKA",
            active=True,
            order=1,
        )
        self.stdout.write(f"Point d'embarquement {point} (créé).")

