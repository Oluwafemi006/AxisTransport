import uuid
from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import apps.core.models


class Migration(migrations.Migration):

    dependencies = [
        ('auth', '0012_alter_user_first_name_max_length'),
        ('core', '0014_receipt_provider_mode'),
    ]

    operations = [
        migrations.CreateModel(
            name='StaffInvitation',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('email', models.EmailField(max_length=254, verbose_name='Adresse e-mail')),
                ('token', models.UUIDField(db_index=True, default=uuid.uuid4, editable=False, unique=True)),
                ('expires_at', models.DateTimeField(default=apps.core.models.default_invitation_expiry, verbose_name="Date d'expiration")),
                ('is_used', models.BooleanField(default=False, verbose_name='Utilisée')),
                ('group', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='staff_invitations', to='auth.group', verbose_name='Groupe de rôles')),
                ('invited_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='sent_staff_invitations', to=settings.AUTH_USER_MODEL, verbose_name='Invité par')),
            ],
            options={
                'verbose_name': 'Invitation du personnel',
                'verbose_name_plural': 'Invitations du personnel',
                'ordering': ['-created_at'],
            },
        ),
    ]

