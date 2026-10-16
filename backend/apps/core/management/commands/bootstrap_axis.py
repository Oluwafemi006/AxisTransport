import os

from django.core.management.base import BaseCommand

from apps.core.models import FeatureFlag, Location, Route, SystemSetting, User, Vehicle


class Command(BaseCommand):
    help = "Initialise uniquement les données confirmées et garde toutes les fonctions à valider désactivées."

    def handle(self, *args, **options):
        cotonou, _ = Location.objects.get_or_create(name="Cotonou")
        parakou, _ = Location.objects.get_or_create(name="Parakou", defaults={"address": "Okédama"})
        Route.objects.get_or_create(origin=cotonou, destination=parakou)
        Route.objects.get_or_create(origin=parakou, destination=cotonou)
        Vehicle.objects.get_or_create(
            category=Vehicle.Category.BUS,
            name="Yutong",
            defaults={"state": Vehicle.State.ACTIVE},
        )
        for key in FeatureFlag.Key.values:
            FeatureFlag.objects.get_or_create(key=key, defaults={"enabled": False})

        # Coordonnées publiques : créées vides, à renseigner par l'administrateur.
        for key, description in (
            ("contact_phone", "Téléphone de contact affiché aux clients"),
            ("contact_whatsapp", "Numéro WhatsApp affiché aux clients"),
        ):
            SystemSetting.objects.get_or_create(key=key, defaults={"value": "", "description": description})

        # Avance de l'embarquement sur l'heure de départ, modifiable par l'administrateur.
        SystemSetting.objects.get_or_create(
            key="boarding_lead_minutes",
            defaults={"value": 30, "description": "Minutes entre l'embarquement et le départ"},
        )

        from apps.core.models import PaymentMethod
        from decimal import Decimal
        from django.conf import settings
        active_provider = getattr(settings, "ACTIVE_PAYMENT_PROVIDER", "fedapay")

        PaymentMethod.objects.get_or_create(
            code="FEDAPAY",
            defaults={
                "label": "FedaPay Mobile Money / Carte",
                "active": (active_provider == "fedapay"),
                # Frais FedaPay supportés par l'agence (décision de la direction) : aucun frais client par défaut.
                "fee_percentage": Decimal("0.00"),
            },
        )
        PaymentMethod.objects.get_or_create(
            code="KKIAPAY",
            defaults={
                "label": "KKiaPay Mobile Money",
                # KKiaPay n'est pas implémenté : jamais actif tant que la vérification réelle n'existe pas.
                "active": False,
                "fee_percentage": Decimal("0.00"),
            },
        )

        username = os.environ.get("AXIS_ADMIN_USERNAME")
        password = os.environ.get("AXIS_ADMIN_PASSWORD")
        if username and password and not User.objects.filter(username=username).exists():
            User.objects.create_superuser(
                username=username,
                password=password,
                email=os.environ.get("AXIS_ADMIN_EMAIL", ""),
                role=User.Role.ADMIN,
            )
            self.stdout.write(self.style.SUCCESS(f"Administrateur {username} créé."))

        # Arrêts de la ligne et grille des prix par tronçon : seulement ce qui manque, rien n'est écrasé.
        from django.core.management import call_command
        from django.core.management.base import CommandError

        try:
            call_command("load_segment_fares", stdout=self.stdout)
        except CommandError as exc:
            self.stdout.write(self.style.WARNING(f"Grille des tronçons non chargée : {exc}"))

        self.stdout.write(self.style.SUCCESS("Données Axis confirmées initialisées."))
        self.stdout.write(
            self.style.WARNING(
                "Capacité, plan de sièges, horaires, tarifs, moyens de paiement et délai de réservation restent à configurer."
            )
        )

