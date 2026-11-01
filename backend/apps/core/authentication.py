"""Jetons JWT : refus de ceux émis avant le dernier changement de mot de passe."""
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings

from .models import User


def issued_before_password_change(user, token):
    if user.password_changed_at is None:
        return False
    return int(token.get("iat", 0)) < int(user.password_changed_at.timestamp())


class AxisJWTAuthentication(JWTAuthentication):
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
