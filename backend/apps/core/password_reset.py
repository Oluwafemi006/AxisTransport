"""Mot de passe oublié (clients, code par e-mail) et changement de mot de passe avec fermeture des sessions."""
import hashlib
import hmac
import logging
import secrets
import threading
from datetime import timedelta

from django.conf import settings
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

from .models import PasswordResetCode, User

logger = logging.getLogger(__name__)

CODE_LIFETIME = timedelta(minutes=15)
MAX_ATTEMPTS = 5
REQUEST_MESSAGE = "Si un compte client correspond à cette adresse, un code vient d'y être envoyé."
INVALID_MESSAGE = "Code incorrect ou expiré."


def normalize_email(value):
    return str(value or "").strip().lower()


def _hash_code(user_id, code):
    # Clé secrète obligatoire : un code à 6 chiffres se retrouverait sinon en un instant depuis la base.
    message = f"{user_id}:{code}".encode()
    return hmac.new(settings.SECRET_KEY.encode(), message, hashlib.sha256).hexdigest()


def _client_for(email):
    """Le client de cette adresse. Une adresse partagée par plusieurs comptes passe par un administrateur."""
    if not email:
        return None
    clients = list(User.objects.filter(email__iexact=email, role=User.Role.CLIENT, is_active=True)[:2])
    if len(clients) > 1:
        logger.warning("Mot de passe oublié : adresse partagée par plusieurs comptes, aucun code envoyé.")
    return clients[0] if len(clients) == 1 else None


def _send(user, code):
    try:
        send_mail(
            subject="Votre code AXIS Transport",
            message=(
                f"Bonjour,\n\n"
                f"Votre code pour changer de mot de passe : {code}\n"
                f"Il est valable 15 minutes et ne sert qu'une fois.\n\n"
                f"Votre identifiant de connexion : {user.username}\n\n"
                f"Si vous n'avez rien demandé, ignorez ce message : votre mot de passe ne change pas.\n\n"
                f"L'équipe AXIS Transport\n"
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
            fail_silently=False,
        )
    except Exception:
        logger.exception("Mot de passe oublié : envoi de l'e-mail impossible.")


def request_code(email):
    user = _client_for(normalize_email(email))
    if user is None:
        return
    code = f"{secrets.randbelow(1_000_000):06d}"
    with transaction.atomic():
        # Un seul code valable à la fois.
        PasswordResetCode.objects.filter(user=user, used_at__isnull=True).update(used_at=timezone.now())
        PasswordResetCode.objects.create(
            user=user, code_hash=_hash_code(user.pk, code), expires_at=timezone.now() + CODE_LIFETIME
        )
    if getattr(settings, "AXIS_PASSWORD_RESET_SYNC_EMAIL", False):
        _send(user, code)
    else:
        # Hors de la requête : la durée de réponse ne doit pas révéler que le compte existe.
        threading.Thread(target=_send, args=(user, code), daemon=True).start()


def close_sessions(user):
    """Ferme toutes les sessions du compte, y compris les jetons d'accès en cours."""
    user.password_changed_at = timezone.now()
    user.save(update_fields=["password_changed_at"])
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)


def change_password(user, password):
    """Change le mot de passe et ferme toutes les sessions, y compris les jetons d'accès en cours."""
    user.set_password(password)
    user.save(update_fields=["password"])
    close_sessions(user)


def confirm_code(email, code, password):
    """Vrai si le code est bon et le mot de passe changé. Chaque échec consomme un des 5 essais."""
    user = _client_for(normalize_email(email))
    if user is None:
        return False
    with transaction.atomic():
        entry = (
            PasswordResetCode.objects.select_for_update()
            .filter(user=user, used_at__isnull=True, expires_at__gt=timezone.now(), attempts__lt=MAX_ATTEMPTS)
            .first()
        )
        if entry is None:
            return False
        if not hmac.compare_digest(entry.code_hash, _hash_code(user.pk, str(code or "").strip())):
            entry.attempts += 1
            entry.save(update_fields=["attempts"])
            return False
        entry.used_at = timezone.now()
        entry.save(update_fields=["used_at"])
        change_password(user, password)
    return True
