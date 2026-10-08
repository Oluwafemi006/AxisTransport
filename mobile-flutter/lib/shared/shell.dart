import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        height: 68,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8F1FB),
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
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Billets',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Suivi colis',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: 'Location',
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

class AxisScaffold extends StatelessWidget {
  const AxisScaffold({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 32),
  });

  final Widget child;
  final String? title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AxisColors.background,
      appBar: title == null ? null : AppBar(title: Text(title!)),
      body: child,
    );
  }
}
