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

        from apps.core.models import PaymentMethod
        from decimal import Decimal
        from django.conf import settings
        active_provider = getattr(settings, "ACTIVE_PAYMENT_PROVIDER", "fedapay")

        PaymentMethod.objects.get_or_create(
            code="FEDAPAY",
            defaults={
                "label": "FedaPay Mobile Money / Carte",
                "active": (active_provider == "fedapay"),
                "fee_percentage": Decimal("1.80"),
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

        self.stdout.write(self.style.SUCCESS("Données Axis confirmées initialisées."))
        self.stdout.write(
            self.style.WARNING(
                "Capacité, plan de sièges, horaires, tarifs, moyens de paiement et délai de réservation restent à configurer."
            )
        )

