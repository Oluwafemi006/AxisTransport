"""Mot de passe oublié des clients (lien à usage unique par e-mail, demandé par le client ou envoyé par l'admin)
et changement de mot de passe avec fermeture des sessions."""
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

from .models import PasswordResetLink, User

logger = logging.getLogger(__name__)

# Durée du lien de réinitialisation (24 h par défaut, réglable) ; il ne sert qu'une fois.
LINK_LIFETIME = timedelta(hours=int(getattr(settings, "AXIS_PASSWORD_LINK_HOURS", 24)))
REQUEST_MESSAGE = "Si un compte client correspond à cette adresse, un lien pour choisir un nouveau mot de passe vient d'y être envoyé."
INVALID_LINK_MESSAGE = "Ce lien n'est plus valable (déjà utilisé, expiré ou remplacé par un plus récent). Demandez-en un nouveau."
CODE_FLOW_MESSAGE = "Les codes ne sont plus utilisés : ouvrez le lien reçu par e-mail pour choisir votre mot de passe."


def normalize_email(value):
    return str(value or "").strip().lower()


def _client_for(email):
    """Le client de cette adresse. Une adresse partagée par plusieurs comptes passe par un administrateur."""
    if not email:
        return None
    clients = list(User.objects.filter(email__iexact=email, role=User.Role.CLIENT, is_active=True)[:2])
    if len(clients) > 1:
        logger.warning("Mot de passe oublié : adresse partagée par plusieurs comptes, aucun code envoyé.")
    return clients[0] if len(clients) == 1 else None


def close_sessions(user):
    """Ferme toutes les sessions du compte, y compris les jetons d'accès en cours."""
    user.password_changed_at = timezone.now()
    user.save(update_fields=["password_changed_at"])
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)


def change_password(user, password):
    """Change le mot de passe et ferme toutes les sessions, y compris les jetons d'accès en cours."""
    user.set_password(password)
    user.must_change_password = False
    user.save(update_fields=["password", "must_change_password"])
    close_sessions(user)


# ─── Lien de réinitialisation ─────────────────────────────────────────────────


def _hash_token(token):
    return hmac.new(settings.SECRET_KEY.encode(), f"reset-link:{token}".encode(), hashlib.sha256).hexdigest()


def link_url(token):
    """Adresse de la page du site ; vide tant que l'adresse publique du site n'est pas configurée."""
    base = (getattr(settings, "FRONTEND_URL", "") or getattr(settings, "PUBLIC_WEB_URL", "")).rstrip("/")
    return f"{base}/nouveau-mot-de-passe?token={token}" if base else ""


def _send_link(user, url):
    """Vrai si l'e-mail est parti. Aucun envoi sans adresse e-mail ou sans adresse du site."""
    if not user.email or not url:
        return False
    hours = int(LINK_LIFETIME.total_seconds() // 3600)
    try:
        send_mail(
            subject="Choisir un nouveau mot de passe AXIS Transport",
            message=(
                f"Bonjour,\n\n"
                f"Pour choisir un nouveau mot de passe, ouvrez ce lien :\n{url}\n\n"
                f"Il est valable {hours} heures et ne sert qu'une fois.\n\n"
                f"Votre identifiant de connexion : {user.username}\n\n"
                f"Si vous n'avez rien demandé, ignorez ce message : votre mot de passe ne change pas.\n\n"
                f"L'équipe AXIS Transport\n"
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
            fail_silently=False,
        )
    except Exception:
        logger.exception("Lien de réinitialisation : envoi de l'e-mail impossible.")
        return False
    return True


def create_link(user, *, created_by=None):
    """Nouveau lien pour un client ; les liens encore valables sont annulés. Renvoie (lien, adresse)."""
    if user.role != User.Role.CLIENT:
        raise ValueError("Le lien de réinitialisation est réservé aux comptes clients.")
    token = secrets.token_urlsafe(32)
    with transaction.atomic():
        PasswordResetLink.objects.filter(user=user, used_at__isnull=True).update(used_at=timezone.now())
        link = PasswordResetLink.objects.create(
            user=user, token_hash=_hash_token(token), expires_at=timezone.now() + LINK_LIFETIME, created_by=created_by,
        )
    return link, link_url(token)


def send_link(user, *, created_by):
    """Envoi par l'admin : (e-mail parti ?, adresse du lien). L'adresse sert au bouton « Copier le lien »."""
    link, url = create_link(user, created_by=created_by)
    sent = _send_link(user, url)
    if sent:
        PasswordResetLink.objects.filter(pk=link.pk).update(email_sent=True)
    return sent, url


def request_link(email):
    """Demande du client lui-même : rien n'est révélé sur l'existence du compte."""
    user = _client_for(normalize_email(email))
    if user is None:
        return
    link, url = create_link(user)

    def deliver():
        if _send_link(user, url):
            PasswordResetLink.objects.filter(pk=link.pk).update(email_sent=True)

    if getattr(settings, "AXIS_PASSWORD_RESET_SYNC_EMAIL", False):
        deliver()
    else:
        # Hors de la requête : la durée de réponse ne doit pas révéler que le compte existe.
        threading.Thread(target=deliver, daemon=True).start()


def _valid_link(token, *, lock=False):
    queryset = PasswordResetLink.objects.select_related("user")
    if lock:
        queryset = queryset.select_for_update()
    return queryset.filter(
        token_hash=_hash_token(str(token or "").strip()), used_at__isnull=True, expires_at__gt=timezone.now(),
        user__is_active=True, user__role=User.Role.CLIENT,
    ).first()


def link_is_valid(token):
    return _valid_link(token) is not None


def use_link(token, password):
    """Vrai si le lien est valable : le mot de passe est changé et toutes les sessions sont fermées."""
    with transaction.atomic():
        link = _valid_link(token, lock=True)
        if link is None:
            return False
        link.used_at = timezone.now()
        link.save(update_fields=["used_at"])
        change_password(link.user, password)
    return True
