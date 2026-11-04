import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("core", "0023_password_reset")]

    operations = [
        migrations.AddField(model_name="staffinvitation", name="first_name", field=models.CharField(blank=True, max_length=150)),
        migrations.AddField(model_name="staffinvitation", name="last_name", field=models.CharField(blank=True, max_length=150)),
        migrations.CreateModel(
            name="AccountChange",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("action", models.CharField(choices=[("CREATED", "Compte créé"), ("INVITED", "Invitation envoyée"), ("ROLE", "Rôle changé"), ("DEACTIVATED", "Compte désactivé"), ("ACTIVATED", "Compte réactivé")], max_length=16)),
                ("detail", models.CharField(blank=True, max_length=255)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("actor", models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="+", to=settings.AUTH_USER_MODEL)),
                ("target", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name="account_changes", to=settings.AUTH_USER_MODEL)),
            ],
            options={"ordering": ["-created_at", "-id"]},
        ),
    ]
