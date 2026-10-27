# Generated manually for boarding and alighting points
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0019_segment_booking_and_stop_offset"),
    ]

    operations = [
        migrations.CreateModel(
            name="BoardingPoint",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("name", models.CharField(max_length=160)),
                ("active", models.BooleanField(default=True)),
                ("order", models.PositiveSmallIntegerField(default=1, help_text="Ordre d'affichage")),
                (
                    "location",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="boarding_points",
                        to="core.location",
                    ),
                ),
            ],
            options={
                "ordering": ["location__name", "order", "name"],
            },
        ),
        migrations.AddConstraint(
            model_name="boardingpoint",
            constraint=models.UniqueConstraint(
                fields=("location", "name"),
                name="unique_boarding_point_per_location",
            ),
        ),
        migrations.AddField(
            model_name="booking",
            name="boarding_point",
            field=models.ForeignKey(
                blank=True,
                help_text="Point d'embarquement choisi dans la ville de départ",
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="bookings_as_boarding_point",
                to="core.boardingpoint",
            ),
        ),
        migrations.AddField(
            model_name="booking",
            name="alighting_point",
            field=models.ForeignKey(
                blank=True,
                help_text="Point de débarquement choisi dans la ville d'arrivée",
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="bookings_as_alighting_point",
                to="core.boardingpoint",
            ),
        ),
        migrations.AddField(
            model_name="booking",
            name="boarding_point_name",
            field=models.CharField(
                blank=True,
                help_text="Copie figée du nom du point d'embarquement au moment de la réservation",
                max_length=160,
            ),
        ),
        migrations.AddField(
            model_name="booking",
            name="alighting_point_name",
            field=models.CharField(
                blank=True,
                help_text="Copie figée du nom du point de débarquement au moment de la réservation",
                max_length=160,
            ),
        ),
        migrations.AddField(
            model_name="ticket",
            name="boarding_point",
            field=models.ForeignKey(
                blank=True,
                help_text="Point d'embarquement choisi dans la ville de départ",
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="tickets_as_boarding_point",
                to="core.boardingpoint",
            ),
        ),
        migrations.AddField(
            model_name="ticket",
            name="alighting_point",
            field=models.ForeignKey(
                blank=True,
                help_text="Point de débarquement choisi dans la ville d'arrivée",
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="tickets_as_alighting_point",
                to="core.boardingpoint",
            ),
        ),
        migrations.AddField(
            model_name="ticket",
            name="boarding_point_name",
            field=models.CharField(
                blank=True,
                help_text="Copie figée du nom du point d'embarquement au moment de l'émission",
                max_length=160,
            ),
        ),
        migrations.AddField(
            model_name="ticket",
            name="alighting_point_name",
            field=models.CharField(
                blank=True,
                help_text="Copie figée du nom du point de débarquement au moment de l'émission",
                max_length=160,
            ),
        ),
    ]

