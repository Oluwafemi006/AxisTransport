import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'core/session.dart';
import 'features/auth/invitation_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/bookings/presentation/booking_review_screen.dart';
import 'features/home/home_screen.dart';
import 'features/parcels/parcels_screen.dart';
import 'features/passengers/presentation/passengers_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/rentals/rentals_screen.dart';
import 'features/sales/sell_ticket_screen.dart';
import 'features/seats/presentation/seat_selection_screen.dart';
import 'features/staff/presentation/controller_parcel_screen.dart';
import 'features/staff/presentation/controller_scanner_screen.dart';
import 'features/staff/presentation/staff_home_screen.dart';
import 'features/staff/presentation/staff_profile_screen.dart';
import 'features/tickets/ticket_screen.dart';
import 'features/tickets/tickets_screen.dart';
import 'features/trips/domain/trip_search.dart';
import 'features/trips/presentation/trip_results_screen.dart';
import 'features/trips/presentation/trip_search_screen.dart';
import 'shared/shell.dart';
import 'staff_router.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Fonction de redirection globale de GoRouter basée sur le rôle serveur.
String? globalRoleRedirect(BuildContext context, GoRouterState state) {
  final session = sessionRouterNotifier.session;

  // Tant que la session n'est pas prête, laisser le routeur naviguer
  if (!session.ready) return null;

  final loc = state.matchedLocation;
  final isAuthRoute = loc == '/connexion' || loc == '/login' || loc == '/inscription';
  final isInvitation = loc.startsWith('/invitation');

  // 1. Utilisateur non connecté
  if (session.user == null) {
    if (isAuthRoute || isInvitation) return null;
    return '/connexion';
  }

  // 2. Utilisateur connecté
  final user = session.user!;

  // Empêche un utilisateur connecté d'accéder aux écrans de connexion/inscription
  if (isAuthRoute) {
    return user.isStaff ? '/staff' : '/';
  }

  // Client qui vise une route contrôleur -> accueil client
  if (user.isClient) {
    final isStaffTarget = loc.startsWith('/staff') || loc == '/scanner' || loc == '/vendre';
    if (isStaffTarget) {
      return '/';
    }
  }

  // Contrôleur qui vise une route client -> accueil contrôleur
  if (user.isStaff) {
    final isClientExclusiveTarget = loc == '/' ||
        loc.startsWith('/billets') ||
        loc.startsWith('/colis') ||
        loc.startsWith('/location');
    if (isClientExclusiveTarget) {
      return '/staff';
    }
  }

  return null;
}

/// Routeur de l'app ; remplacé par [resetAxisRouter] quand un autre compte se connecte.
GoRouter axisRouter = buildAxisRouter();

/// Nouveau routeur vierge : aucun onglet ni écran d'un compte précédent n'est conservé.
void resetAxisRouter() {
  final previous = axisRouter;
  axisRouter = buildAxisRouter();
  previous.dispose();
}

GoRouter buildAxisRouter() => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: sessionRouterNotifier,
  redirect: globalRoleRedirect,
  routes: [
    // ── Routes publiques (communes) ──────────────────────────────────────────
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/connexion',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/login',
      redirect: (context, state) => '/connexion',
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/inscription',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/invitation',
      builder: (context, state) => InvitationScreen(
        token: state.uri.queryParameters['token'],
      ),
    ),

    // ── Zone 1 : Espace Client (ShellRoute avec nav client 5 onglets) ────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/billets',
              builder: (context, state) => const TicketsScreen(),
              routes: [
                GoRoute(
                  path: 'recherche',
                  builder: (context, state) => TripSearchScreen(
                    initialSearch: TripSearch.fromQueryParameters(
                      state.uri.queryParameters,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'resultats',
                  builder: (context, state) {
                    final search = TripSearch.fromQueryParameters(
                      state.uri.queryParameters,
                    );
                    return search == null
                        ? const TripSearchScreen()
                        : TripResultsScreen(search: search);
                  },
                ),
                GoRoute(
                  path: 'booking/:id',
                  redirect: (context, state) =>
                      '/billets/booking/${state.pathParameters['id']}/passagers',
                ),
                GoRoute(
                  path: 'booking/:id/passagers',
                  builder: (context, state) => PassengersScreen(
                    tripId: int.parse(state.pathParameters['id']!),
                    passengerCount: int.tryParse(
                          state.uri.queryParameters['passagers'] ?? '1',
                        ) ??
                        1,
                    originId: int.tryParse(
                      state.uri.queryParameters['origin'] ?? '',
                    ),
                    destinationId: int.tryParse(
                      state.uri.queryParameters['destination'] ?? '',
                    ),
                  ),
                ),
                GoRoute(
                  path: 'booking/:id/sieges',
                  builder: (context, state) => SeatSelectionScreen(
                    tripId: int.parse(state.pathParameters['id']!),
                  ),
                ),
                GoRoute(
                  path: 'booking/:id/recapitulatif',
                  builder: (context, state) => BookingReviewScreen(
                    tripId: int.parse(state.pathParameters['id']!),
                  ),
                ),
                GoRoute(
                  path: 'ticket/:id',
                  builder: (context, state) => TicketScreen(
                    ticketId: int.parse(state.pathParameters['id']!),
                    initialTicket: state.extra as Ticket?,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/location',
              builder: (context, state) => const RentalsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/colis',
              builder: (context, state) => const ParcelsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profil',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),

    // ── Zone 2 : Espace Contrôleur / Staff (ShellRoute avec nav contrôleur) ───
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          StaffShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/staff',
              builder: (context, state) => const StaffHomeScreen(),
              routes: [
                GoRoute(
                  path: 'colis',
                  builder: (context, state) => const ControllerParcelScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scanner',
              builder: (context, state) => const ControllerScannerScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/vendre',
              builder: (context, state) => const SellTicketScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/staff/profil',
              builder: (context, state) => const StaffProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
