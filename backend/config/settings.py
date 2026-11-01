from pathlib import Path
import os
import tempfile

import dj_database_url
from corsheaders.defaults import default_headers


BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "unsafe-development-key")
DEBUG = os.environ.get("DJANGO_DEBUG", "false").lower() == "true"
# « local » seulement sur le poste de développement (compose.yaml) : autorise les données de démonstration.
AXIS_ENVIRONMENT = os.environ.get("AXIS_ENVIRONMENT", "").strip().lower()
ALLOWED_HOSTS = [
    host.strip()
    for host in os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")
    if host.strip()
]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "apps.core",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    # Sert les fichiers statiques (administration Django) sous gunicorn.
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    }
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

if os.environ.get("USE_SQLITE", "false").lower() == "true":
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}
else:
    DATABASES = {
        "default": dj_database_url.config(
            default="postgresql://axis:axis@localhost:5432/axis_transport",
            conn_max_age=600,
            conn_health_checks=True,
        )
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# Cache partagé entre les processus gunicorn d'une même machine : les limites de requêtes
# sont ainsi comptées une seule fois, et non par processus.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
        "LOCATION": os.environ.get("AXIS_CACHE_DIR", os.path.join(tempfile.gettempdir(), "axis-cache")),
    }
}

LANGUAGE_CODE = "fr-fr"
TIME_ZONE = "Africa/Porto-Novo"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
# En debug, les fichiers statiques sont servis sans « collectstatic ».
WHITENOISE_USE_FINDERS = DEBUG
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "core.User"

CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("DJANGO_CORS_ALLOWED_ORIGINS", "http://localhost:3000").split(",")
    if origin.strip()
]
CORS_ALLOW_CREDENTIALS = True
# Adresses HTTPS depuis lesquelles les formulaires de /django-admin/ sont acceptés (ex. adresse d'un tunnel).
CSRF_TRUSTED_ORIGINS = [
    origin.strip() for origin in os.environ.get("DJANGO_CSRF_TRUSTED_ORIGINS", "").split(",") if origin.strip()
]
# En-têtes par défaut, plus le jeton d'une réservation faite sans compte (seul en-tête propre à Axis).
CORS_ALLOW_HEADERS = (*default_headers, "x-booking-token")

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "apps.core.authentication.AxisJWTAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    # Suivi de colis public : nombre de recherches autorisées par adresse IP.
    "DEFAULT_THROTTLE_RATES": {
        "payment_refresh": os.environ.get("AXIS_PAYMENT_REFRESH_RATE", "20/min"),
        "parcel_tracking": os.environ.get("AXIS_PARCEL_TRACKING_RATE", "20/min"),
        "public_ticket": os.environ.get("AXIS_PUBLIC_TICKET_RATE", "60/min"),
        # Connexion et inscription : blocage temporaire au-delà de ces seuils (propositions, réglables).
        "login_account_address": os.environ.get("AXIS_LOGIN_RATE_ACCOUNT_ADDRESS", "10/hour"),
        "login_account": os.environ.get("AXIS_LOGIN_RATE_ACCOUNT", "50/hour"),
        "login_address": os.environ.get("AXIS_LOGIN_RATE_ADDRESS", "30/min"),
        "register_address": os.environ.get("AXIS_REGISTER_RATE_ADDRESS", "10/hour"),
        # Mot de passe oublié : demandes par adresse e-mail et par IP, saisies du code par IP.
        "password_reset_email": os.environ.get("AXIS_PASSWORD_RESET_RATE_EMAIL", "3/hour"),
        "password_reset_address": os.environ.get("AXIS_PASSWORD_RESET_RATE_ADDRESS", "20/hour"),
        "password_reset_confirm": os.environ.get("AXIS_PASSWORD_RESET_CONFIRM_RATE", "30/hour"),
    },
    # Nombre de proxys de confiance devant l'API (pour lire la vraie adresse IP du client).
    "NUM_PROXIES": int(os.environ["AXIS_NUM_PROXIES"]) if os.environ.get("AXIS_NUM_PROXIES") else None,
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 50,
    "DEFAULT_RENDERER_CLASSES": (
        "rest_framework.renderers.JSONRenderer",
        *(("rest_framework.renderers.BrowsableAPIRenderer",) if DEBUG else ()),
    ),
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": __import__("datetime").timedelta(minutes=30),
    "REFRESH_TOKEN_LIFETIME": __import__("datetime").timedelta(days=7),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "TOKEN_REFRESH_SERIALIZER": "apps.core.authentication.AxisTokenRefreshSerializer",
}

# --- Payment Provider Configuration ---
ACTIVE_PAYMENT_PROVIDER = os.environ.get("ACTIVE_PAYMENT_PROVIDER", "fedapay").lower()

# Adresse publique du site, utilisée pour les liens de billets. Aucune valeur par défaut :
# tant qu'elle n'est pas renseignée, aucun lien n'est fabriqué.
PUBLIC_WEB_URL = os.environ.get("PUBLIC_WEB_URL", "").strip().rstrip("/")

# --- FedaPay Configuration ---
FEDAPAY_SECRET_KEY = os.environ.get("FEDAPAY_SECRET_KEY", "")
FEDAPAY_WEBHOOK_SECRET = os.environ.get("FEDAPAY_WEBHOOK_SECRET", "")
FEDAPAY_ENVIRONMENT = os.environ.get("FEDAPAY_ENVIRONMENT", "sandbox").lower()  # 'sandbox' ou 'live'
# Adresse vers laquelle FedaPay renvoie le client après le paiement.
# Vide si ni cette variable ni PUBLIC_WEB_URL ne sont renseignées : aucune adresse de retour n'est alors envoyée.
FEDAPAY_CALLBACK_URL = os.environ.get(
    "FEDAPAY_CALLBACK_URL", f"{PUBLIC_WEB_URL}/paiement/retour" if PUBLIC_WEB_URL else ""
).strip()
# Écart maximal accepté entre l'horodatage signé du webhook et l'heure du serveur (0 = pas de contrôle).
FEDAPAY_WEBHOOK_TOLERANCE_SECONDS = int(os.environ.get("FEDAPAY_WEBHOOK_TOLERANCE_SECONDS", "300"))

# Rattrapage des paiements non confirmés (commande « reconcile_payments », à planifier).
AXIS_PAYMENT_RECONCILE_ENABLED = os.environ.get("AXIS_PAYMENT_RECONCILE_ENABLED", "true").lower() == "true"
# Durée pendant laquelle une transaction créée est réinterrogée. 1440 min = 24 h : durée de validité observée
# du lien de paiement FedaPay (un client peut encore payer pendant ce temps).
AXIS_PAYMENT_RECONCILE_WINDOW_MINUTES = int(os.environ.get("AXIS_PAYMENT_RECONCILE_WINDOW_MINUTES", "1440"))
# Nombre maximal de transactions interrogées par passage : borne les appels à l'API du prestataire.
AXIS_PAYMENT_RECONCILE_BATCH = int(os.environ.get("AXIS_PAYMENT_RECONCILE_BATCH", "20"))

# --- Paiement simulé ---
# Actif uniquement si DEBUG est vrai ET si la variable est explicitement activée. Jamais en production.
AXIS_PAYMENT_SIMULATION = DEBUG and os.environ.get("AXIS_PAYMENT_SIMULATION", "false").lower() == "true"

# Journal des paiements (rattrapages, incidents) sur la sortie standard du processus.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"axis": {"format": "%(asctime)s %(levelname)s %(name)s : %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "axis"}},
    "loggers": {"axis.payments": {"handlers": ["console"], "level": "INFO", "propagate": False}},
}

# --- Photos des colis (Cloudinary) ---
CLOUDINARY_CLOUD_NAME = os.environ.get("CLOUDINARY_CLOUD_NAME", "")
CLOUDINARY_API_KEY = os.environ.get("CLOUDINARY_API_KEY", "")
CLOUDINARY_API_SECRET = os.environ.get("CLOUDINARY_API_SECRET", "")

# --- Messagerie SMTP (Gmail) ---
EMAIL_BACKEND = os.environ.get("EMAIL_BACKEND", "django.core.mail.backends.smtp.EmailBackend")
EMAIL_HOST = os.environ.get("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", "587"))
EMAIL_USE_TLS = os.environ.get("EMAIL_USE_TLS", "true").lower() == "true"
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", EMAIL_HOST_USER or "contact@axistransportlogistique.com")

FRONTEND_URL = os.environ.get("FRONTEND_URL", PUBLIC_WEB_URL).rstrip("/")
