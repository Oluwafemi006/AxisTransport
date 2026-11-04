from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("core", "0024_account_admin")]

    operations = [
        migrations.AlterField(
            model_name="accountchange",
            name="action",
            field=models.CharField(
                choices=[
                    ("CREATED", "Compte créé"), ("INVITED", "Invitation envoyée"), ("ROLE", "Rôle changé"),
                    ("DEACTIVATED", "Compte désactivé"), ("ACTIVATED", "Compte réactivé"),
                    ("UPDATED", "Coordonnées modifiées"), ("PAYMENT", "Moyen de paiement modifié"),
                ],
                max_length=16,
            ),
        ),
    ]
