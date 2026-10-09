from django.core.management.base import BaseCommand

from apps.core.payments import reconcile_pending_payments


class Command(BaseCommand):
    help = (
        "Rattrape les paiements FedaPay jamais confirmés (ni par le client, ni par le webhook) : "
        "réinterroge le prestataire et émet les billets par le même chemin que le webhook."
    )

    def handle(self, *args, **options):
        counts = reconcile_pending_payments()
        self.stdout.write(
            "Rattrapage : {checked} interrogée(s), {settled} billet(s) émis, {refund_due} à rembourser, "
            "{refused} refusée(s), {pending} en attente, {abandoned} abandonnée(s), {anomalies} anomalie(s).".format(**counts)
        )
