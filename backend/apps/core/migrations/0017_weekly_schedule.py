from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0016_default_staff_groups"),
    ]

    operations = [
        migrations.CreateModel(
            name="WeeklySchedule",
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
                    "day_of_week",
                    models.IntegerField(
                        choices=[
                            (0, "Lundi"),
                            (1, "Mardi"),
                            (2, "Mercredi"),
                            (3, "Jeudi"),
                            (4, "Vendredi"),
                            (5, "Samedi"),
                            (6, "Dimanche"),
                        ],
                        db_index=True,
                    ),
                ),
                ("departure_time", models.TimeField(blank=True, null=True)),
                (
                    "is_active",
                    models.BooleanField(
                        default=True,
                        help_text="Actif si un trajet est opéré ce jour, inactif si repos.",
                    ),
                ),
                (
                    "notes",
                    models.CharField(
                        blank=True,
                        help_text="Remarques (ex: Repos/Visite technique)",
                        max_length=255,
                    ),
                ),
                (
                    "route",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="weekly_schedules",
                        to="core.route",
                    ),
                ),
                (
                    "vehicle",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="weekly_schedules",
                        to="core.vehicle",
                    ),
                ),
            ],
            options={
                "verbose_name": "Planning hebdomadaire",
                "verbose_name_plural": "Plannings hebdomadaires",
                "ordering": ["day_of_week", "departure_time"],
            },
        ),
        migrations.AddConstraint(
            model_name="trip",
            constraint=models.CheckConstraint(
                check=models.Q(
                    ("arrival_at__isnull", True),
                    ("arrival_at__gt", models.F("departure_at")),
                    _connector="OR",
                ),
                name="trip_arrival_after_departure",
            ),
        ),
    ]
