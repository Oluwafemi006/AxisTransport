"""Jetons JWT : refus de ceux émis avant le dernier changement de mot de passe."""
from rest_framework.exceptions import PermissionDenied
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings

from .models import User


def issued_before_password_change(user, token):
    if user.password_changed_at is None:
        return False
    return int(token.get("iat", 0)) < int(user.password_changed_at.timestamp())


# Seules adresses permises tant que le mot de passe provisoire n'est pas remplacé.
PASSWORD_CHANGE_PATHS = ("/auth/me/", "/auth/password/change/")


class PasswordChangeRequired(PermissionDenied):
    default_detail = "Choisissez un nouveau mot de passe avant de continuer."
    default_code = "password_change_required"


class AxisJWTAuthentication(JWTAuthentication):
    def authenticate(self, request):
        result = super().authenticate(request)
        if result is not None and getattr(result[0], "must_change_password", False):
            path = request.path
            allowed = path.endswith(PASSWORD_CHANGE_PATHS[1]) or (path.endswith(PASSWORD_CHANGE_PATHS[0]) and request.method == "GET")
            if not allowed:
                raise PasswordChangeRequired()
        return result

    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        if issued_before_password_change(user, validated_token):
            raise InvalidToken("Session fermée : reconnectez-vous.")
        return user


class AxisTokenRefreshSerializer(TokenRefreshSerializer):
    def validate(self, attrs):
        # Les jetons renouvelés ne sont pas tous en liste noire : le contrôle de date les couvre.
        token = self.token_class(attrs["refresh"])
        user = User.objects.filter(pk=token.get(api_settings.USER_ID_CLAIM)).first()
        if user and issued_before_password_change(user, token):
            raise InvalidToken("Session fermée : reconnectez-vous.")
        return super().validate(attrs)
