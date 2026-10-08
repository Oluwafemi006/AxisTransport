from rest_framework.permissions import BasePermission

from .models import User


class HasAnyRole(BasePermission):
    roles = set()

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role in self.roles)


class IsAxisAdmin(HasAnyRole):
    roles = {User.Role.ADMIN}


class IsControllerOrAdmin(HasAnyRole):
    roles = {User.Role.CONTROLLER, User.Role.ADMIN}


class IsCounterOrAdmin(HasAnyRole):
    roles = {User.Role.COUNTER, User.Role.ADMIN}


class IsOperationsStaff(HasAnyRole):
    roles = {User.Role.COUNTER, User.Role.CONTROLLER, User.Role.ADMIN}


class IsClient(HasAnyRole):
    roles = {User.Role.CLIENT}


class IsClientCounterOrAdmin(HasAnyRole):
    roles = {User.Role.CLIENT, User.Role.COUNTER, User.Role.ADMIN}


# ─── Surface Client stricte ──────────────────────────────────────────────────
# Utilisée exclusivement sur /api/v1/client/.
# Refuse explicitement toute personne authentifiée qui N'EST PAS un CLIENT.
# Le personnel interne (COUNTER, CONTROLLER, ADMIN) doit utiliser
# les surfaces /staff/ ou /admin/ qui seront créées ultérieurement.
class IsClientOnly(BasePermission):
    """
    Autorise uniquement les utilisateurs avec le rôle CLIENT.
    Refuse COUNTER, CONTROLLER, ADMIN même s'ils sont authentifiés.
    Cette permission est strictement destinée à la surface /api/v1/client/.
    """
    message = "Cette opération est réservée aux clients. Le personnel doit utiliser l'interface interne."

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == User.Role.CLIENT
        )
