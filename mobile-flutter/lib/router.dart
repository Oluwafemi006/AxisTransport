import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/parcels/parcels_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/rentals/rentals_screen.dart';
import 'features/bookings/presentation/booking_review_screen.dart';
import 'features/passengers/presentation/passengers_screen.dart';
import 'features/seats/presentation/seat_selection_screen.dart';
import 'features/tickets/ticket_screen.dart';
import 'features/tickets/tickets_screen.dart';
import 'features/trips/domain/trip_search.dart';
import 'features/trips/presentation/trip_results_screen.dart';
import 'features/trips/presentation/trip_search_screen.dart';
import 'shared/shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final axisRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
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
                    passengerCount:
                        int.tryParse(
                          state.uri.queryParameters['passagers'] ?? '1',
                        ) ??
                        1,
                    originId: int.tryParse(state.uri.queryParameters['origin'] ?? ''),
                    destinationId: int.tryParse(state.uri.queryParameters['destination'] ?? ''),
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
              path: '/colis',
              builder: (context, state) => const ParcelsScreen(),
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
              path: '/profil',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
