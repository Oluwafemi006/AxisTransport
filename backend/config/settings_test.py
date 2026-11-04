from .settings import *  # noqa: F401,F403

# Réglage réservé aux tests : hachage rapide des mots de passe.
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

# Les tests n'envoient jamais de vrais e-mails : stockage en mémoire dans mail.outbox.
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
# Envoi immédiat du code, pour le lire dans mail.outbox.
AXIS_PASSWORD_RESET_SYNC_EMAIL = True

# Les tests réutilisent les mêmes téléphones et le même cache : seuils de réservation relevés ici,
# les tests des limites les abaissent eux-mêmes (test_booking_limits).
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"].update({"booking_address": "10000/hour", "booking_phone": "10000/hour"})  # noqa: F405
AXIS_BOOKING_MAX_HELD = 1000
AXIS_BOOKING_MAX_HELD_SEATS = 100000
