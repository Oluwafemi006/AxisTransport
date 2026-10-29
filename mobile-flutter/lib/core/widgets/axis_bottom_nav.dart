import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Rôle ciblé par [AxisBottomNav] pour déterminer la disposition des onglets.
enum AxisBottomNavRole {
  /// 5 onglets : Accueil, Billets, Location, Colis, Profil.
  client,

  /// 4 onglets : Accueil, Scanner, Historique, Profil.
  controller,
}

/// Description d'un onglet de la barre de navigation.
class AxisBottomNavItem {
  const AxisBottomNavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

/// Barre de navigation inférieure commune de l'application AXIS.
class AxisBottomNav extends StatelessWidget {
  const AxisBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.role = AxisBottomNavRole.client,
    this.customItems,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final AxisBottomNavRole role;
  final List<AxisBottomNavItem>? customItems;

  static const List<AxisBottomNavItem> clientItems = [
    AxisBottomNavItem(
      label: 'Accueil',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    AxisBottomNavItem(
      label: 'Billets',
      icon: Icons.confirmation_number_outlined,
      activeIcon: Icons.confirmation_number_rounded,
    ),
    AxisBottomNavItem(
      label: 'Location',
      icon: Icons.directions_car_outlined,
      activeIcon: Icons.directions_car_rounded,
    ),
    AxisBottomNavItem(
      label: 'Colis',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
    ),
    AxisBottomNavItem(
      label: 'Profil',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  static const List<AxisBottomNavItem> controllerItems = [
    AxisBottomNavItem(
      label: 'Accueil',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
    ),
    AxisBottomNavItem(
      label: 'Scanner',
      icon: Icons.qr_code_scanner_rounded,
      activeIcon: Icons.qr_code_scanner_rounded,
    ),
    AxisBottomNavItem(
      label: 'Historique',
      icon: Icons.history_rounded,
      activeIcon: Icons.history_rounded,
    ),
    AxisBottomNavItem(
      label: 'Profil',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    final items = customItems ??
        (role == AxisBottomNavRole.controller
            ? controllerItems
            : clientItems);

    final activeColor = role == AxisBottomNavRole.controller
        ? tokens.ink
        : theme.colorScheme.primary;
    final inactiveColor = tokens.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: tokens.border,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AxisSpacing.xs,
            vertical: AxisSpacing.xxs,
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == currentIndex;
              final color = isSelected ? activeColor : inactiveColor;

              return Expanded(
                child: Semantics(
                  label: item.label,
                  button: true,
                  selected: isSelected,
                  child: InkWell(
                    onTap: () => onTap(index),
                    borderRadius: BorderRadius.circular(AxisRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AxisSpacing.xs,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected && item.activeIcon != null
                                ? item.activeIcon
                                : item.icon,
                            size: 22,
                            color: color,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

