from .settings import *  # noqa: F401,F403

# Réglage réservé aux tests : hachage rapide des mots de passe.
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
