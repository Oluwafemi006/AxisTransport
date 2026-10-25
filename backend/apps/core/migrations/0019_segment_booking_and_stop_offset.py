# Generated manually for segment booking and stop offset
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0018_routestop"),
    ]

    operations = [
        migrations.AddField(
            model_name="routestop",
            name="offset_minutes",
            field=models.PositiveIntegerField(
                blank=True,
                help_text="Décalage en minutes depuis le départ du terminus pour cette escale (optionnel)",
                null=True,
            ),
        ),
        migrations.AddField(
            model_name="booking",
            name="origin",
            field=models.ForeignKey(
                blank=True,
                help_text="Arrêt de montée du voyageur (null = départ du trajet complet)",
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="bookings_as_origin",
                to="core.location",
            ),
        ),
        migrations.AddField(
            model_name="booking",
            name="destination",
            field=models.ForeignKey(
                blank=True,
                help_text="Arrêt de descente du voyageur (null = terminus du trajet complet)",
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="bookings_as_destination",
                to="core.location",
            ),
        ),
        migrations.AddField(
            model_name="ticket",
            name="origin",
            field=models.ForeignKey(
                blank=True,
                help_text="Arrêt de montée du passager (null = départ du trajet complet)",
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="tickets_as_origin",
                to="core.location",
            ),
        ),
        migrations.AddField(
            model_name="ticket",
            name="destination",
            field=models.ForeignKey(
                blank=True,
                help_text="Arrêt de descente du passager (null = terminus du trajet complet)",
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="tickets_as_destination",
                to="core.location",
            ),
        ),
    ]

