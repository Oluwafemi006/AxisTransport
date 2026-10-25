# Generated manually for RouteStop
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0017_weekly_schedule"),
    ]

    operations = [
        migrations.CreateModel(
            name="RouteStop",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "position",
                    models.PositiveSmallIntegerField(
                        help_text="Ordre de l'étape sur cet itinéraire (1, 2, ...)"
                    ),
                ),
                (
                    "location",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="route_stops",
                        to="core.location",
                    ),
                ),
                (
                    "route",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="stops",
                        to="core.route",
                    ),
                ),
            ],
            options={
                "verbose_name": "Étape d'itinéraire",
                "verbose_name_plural": "Étapes d'itinéraire",
                "ordering": ["route", "position"],
            },
        ),
        migrations.AddConstraint(
            model_name="routestop",
            constraint=models.UniqueConstraint(
                fields=("route", "position"), name="unique_route_stop_position"
            ),
        ),
        migrations.AddConstraint(
            model_name="routestop",
            constraint=models.UniqueConstraint(
                fields=("route", "location"), name="unique_route_stop_location"
            ),
        ),
    ]
