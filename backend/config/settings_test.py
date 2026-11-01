from .settings import *  # noqa: F401,F403

# Réglage réservé aux tests : hachage rapide des mots de passe.
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

# Les tests n'envoient jamais de vrais e-mails : stockage en mémoire dans mail.outbox.
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
# Envoi immédiat du code, pour le lire dans mail.outbox.
AXIS_PASSWORD_RESET_SYNC_EMAIL = True
