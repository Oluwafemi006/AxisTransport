import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/axis_spacing.dart';
import 'core/theme/axis_tokens.dart';
import 'features/sales/sell_ticket_screen.dart';
import 'features/staff/presentation/controller_parcel_screen.dart';
import 'features/staff/presentation/controller_scanner_screen.dart';
import 'features/staff/presentation/staff_home_screen.dart';
import 'features/staff/presentation/staff_profile_screen.dart';

/// Navigation du personnel (COUNTER, CONTROLLER, ADMIN) : Accueil, Scanner, Vendre, Profil.
/// Elle n'est construite que pour un compte du personnel ; un client n'y a jamais accès.
GoRouter buildStaffRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          StaffShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const StaffHomeScreen(),
              routes: [
                GoRoute(
                  path: 'staff/colis',
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
              path: '/profil',
              builder: (context, state) => const StaffProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class StaffShell extends StatelessWidget {
  const StaffShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        height: AxisSizes.navigationBar,
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: axis.accentSoft,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Vendre',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
