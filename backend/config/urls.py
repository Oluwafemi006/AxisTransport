from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from apps.core.views import MeView, RegisterView
from apps.core.urls_client import client_urlpatterns
from apps.core.urls_staff import staff_urlpatterns

urlpatterns = [
    path("django-admin/", admin.site.urls),

    # ── Auth (partagée, utilisée par toutes les surfaces) ──────────────────
    path("api/v1/auth/token/", TokenObtainPairView.as_view(), name="v1_token_obtain_pair"),
    path("api/v1/auth/token/refresh/", TokenRefreshView.as_view(), name="v1_token_refresh"),
    path("api/v1/auth/register/", RegisterView.as_view(), name="v1_register"),
    path("api/v1/auth/me/", MeView.as_view(), name="v1_me"),

    # ── Surface CLIENT (/api/v1/client/) ────────────────────────────────────
    # Accès strictement réservé aux clients mobiles.
    path("api/v1/client/", include(client_urlpatterns)),

    # ── Surface STAFF (/api/v1/staff/) ──────────────────────────────────────
    # Accès strictement réservé aux employés (Contrôleurs, Secrétaires).
    path("api/v1/staff/", include(staff_urlpatterns)),

    # ── Routes legacy (conservées pendant la migration Flutter) ─────────────
    # NE PAS SUPPRIMER avant validation complète de la migration.
    # Ces routes seront dépréciées en Phase C (après basculement Flutter).
    path("api/v1/auth/token/", TokenObtainPairView.as_view(), name="v1_token_obtain_pair_compat"),
    path("api/v1/auth/token/refresh/", TokenRefreshView.as_view(), name="v1_token_refresh_compat"),
    path("api/v1/", include("apps.core.urls")),
    path("api/auth/token/", TokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("api/auth/token/refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    path("api/", include("apps.core.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

