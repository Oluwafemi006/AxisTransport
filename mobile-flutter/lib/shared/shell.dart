import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/axis_bottom_nav.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: AxisBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: title == null ? null : AppBar(title: Text(title!)),
      body: child,
    );
  }
}
