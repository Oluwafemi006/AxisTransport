"""Vérification de l'e-mail d'un client par un code à 6 chiffres envoyé à cette adresse.
Le code (son HMAC seulement) vit dans le cache : aucune table de plus, valable 30 minutes, 5 essais."""
import hashlib
import hmac
import logging
import secrets

from django.conf import settings
from django.core.cache import cache
from django.core.mail import send_mail

logger = logging.getLogger(__name__)

CODE_LIFETIME_SECONDS = 30 * 60
MAX_ATTEMPTS = 5
NOT_CONFIGURED_MESSAGE = (
    "L'envoi d'e-mails n'est pas encore disponible. Votre e-mail est enregistré mais pas vérifié : réessayez plus tard."
)
SEND_FAILED_MESSAGE = "L'e-mail n'a pas pu être envoyé. Vérifiez l'adresse ou réessayez plus tard."
WRONG_CODE_MESSAGE = "Code incorrect ou expiré. Demandez un nouveau code."


class EmailNotSent(Exception):
    """L'e-mail n'est pas parti : message français prêt à afficher."""


def _key(user):
    return f"email-verification:{user.pk}"


def _hash(user, email, code):
    return hmac.new(settings.SECRET_KEY.encode(), f"email-verify:{user.pk}:{email}:{code}".encode(), hashlib.sha256).hexdigest()


def email_configured():
    """Faux tant que le serveur d'envoi (SMTP) n'est pas renseigné ; les autres moyens d'envoi (tests) comptent comme configurés."""
    if settings.EMAIL_BACKEND == "django.core.mail.backends.smtp.EmailBackend":
        return bool(settings.EMAIL_HOST and settings.DEFAULT_FROM_EMAIL)
    return True


def send_code(user):
    """Envoie un nouveau code à l'e-mail actuel du compte. Lève EmailNotSent si rien n'est parti."""
    email = (user.email or "").strip().lower()
    if not email:
        raise EmailNotSent("Ajoutez d'abord une adresse e-mail.")
    if not email_configured():
        raise EmailNotSent(NOT_CONFIGURED_MESSAGE)
    code = f"{secrets.randbelow(1_000_000):06d}"
    try:
        send_mail(
            subject="Votre code de vérification AXIS Transport",
            message=(
                f"Bonjour,\n\nVotre code de vérification : {code}\n\n"
                f"Il est valable 30 minutes. Saisissez-le dans votre profil pour confirmer cette adresse.\n\n"
                f"Si vous n'avez rien demandé, ignorez ce message.\n\nL'équipe AXIS Transport\n"
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            fail_silently=False,
        )
    except Exception:
        logger.exception("Vérification de l'e-mail : envoi impossible.")
        raise EmailNotSent(SEND_FAILED_MESSAGE)
    cache.set(_key(user), {"hash": _hash(user, email, code), "attempts": 0}, CODE_LIFETIME_SECONDS)


def verify_code(user, code):
    """Vrai si le code correspond à l'e-mail actuel : le compte est alors marqué vérifié."""
    entry = cache.get(_key(user))
    email = (user.email or "").strip().lower()
    if not entry or not email or entry["attempts"] >= MAX_ATTEMPTS:
        return False
    if not hmac.compare_digest(entry["hash"], _hash(user, email, str(code or "").strip())):
        entry["attempts"] += 1
        cache.set(_key(user), entry, CODE_LIFETIME_SECONDS)
        return False
    cache.delete(_key(user))
    user.email_verified = True
    user.save(update_fields=["email_verified"])
    return True


def forget_code(user):
    cache.delete(_key(user))
