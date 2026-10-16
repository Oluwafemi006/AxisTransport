from decimal import Decimal

from django.db import migrations


def no_client_fee(apps, schema_editor):
    # Décision de la direction : le client paie le prix affiché, les frais FedaPay sont supportés par l'agence.
    # Le taux reste modifiable ensuite par l'administrateur.
    apps.get_model("core", "PaymentMethod").objects.exclude(fee_percentage=Decimal("0")).update(
        fee_percentage=Decimal("0.00")
    )


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0011_ticket_status_manual"),
    ]

    operations = [
        migrations.RunPython(no_client_fee, migrations.RunPython.noop),
    ]
