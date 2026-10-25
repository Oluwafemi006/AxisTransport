from django.db import migrations


def create_default_staff_groups(apps, schema_editor):
    Group = apps.get_model("auth", "Group")
    for group_name in ["Guichetier", "Superviseur", "Contrôleur"]:
        Group.objects.get_or_create(name=group_name)


def remove_default_staff_groups(apps, schema_editor):
    Group = apps.get_model("auth", "Group")
    Group.objects.filter(name__in=["Guichetier", "Superviseur", "Contrôleur"]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('auth', '0012_alter_user_first_name_max_length'),
        ('core', '0015_staff_invitation'),
    ]

    operations = [
        migrations.RunPython(create_default_staff_groups, remove_default_staff_groups),
    ]

