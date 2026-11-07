// Audit des largeurs (320, 360, 390 ; texte 1,0 et 1,3) des écrans qui n'ont pas d'autre test d'affichage.
import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/app_lock.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/auth/forced_password_screen.dart';
import 'package:axis_transport_flutter/features/profile/account_screen.dart';
import 'package:axis_transport_flutter/features/profile/connection_settings_screen.dart';
import 'package:axis_transport_flutter/features/profile/delete_account_screen.dart';
import 'package:axis_transport_flutter/features/profile/edit_profile_screen.dart';
import 'package:axis_transport_flutter/features/profile/profile_menu.dart';
import 'package:axis_transport_flutter/features/profile/profile_screen.dart';
import 'package:axis_transport_flutter/features/sold/sold_today_screen.dart';
import 'package:axis_transport_flutter/features/staff/presentation/staff_profile_screen.dart';
import 'package:axis_transport_flutter/features/tickets/tickets_screen.dart';
import 'package:axis_transport_flutter/features/trips/presentation/trip_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/layout_audit.dart';

User _user(String role) => User(
      id: 3, username: 'TEST.compte-avec-un-identifiant-long', firstName: 'Awa-Marie-Christelle', lastName: 'TEST AHOUANDJINOU',
      phone: '+229 01 97 00 00 12', role: role, email: 'awa.marie.christelle.test@exemple.test',
    );

class _Session extends SessionNotifier {
  _Session(this.role);
  final String role;
  @override
  SessionState build() => SessionState(user: _user(role), ready: true);
}

class _Gate implements BiometricGate {
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> authenticate(String reason) async => true;
}

class _Prefs implements AppLockPrefs {
  @override
  Future<bool> read() async => false;
  @override
  Future<void> write(bool enabled) async {}
}

class _Api extends ApiClient {
  @override
  Future<Map<String, String>> contact() async => {'phone': '+229 01 00 00 00 00', 'whatsapp': '+229 01 00 00 00 00'};
  @override
  Future<List<Ticket>> tickets() async => [];
  @override
  Future<List<BookingReservation>> myBookings() async => [];
  @override
  Future<List<Parcel>> parcels() async => [];
  @override
  Future<List<RentalBooking>> rentals() async => [];
  @override
  Future<List<Trip>> trips() async => [];
  @override
  Future<List<Place>> locations() async => [];
  @override
  Future<User> me() async => _user('CLIENT');
  @override
  Future<Map<String, dynamic>> saleSummary() async =>
      {'scanned_tickets': 1234, 'sold_tickets': 5678, 'parcels': 910, 'cash_fcfa': 12345000, 'mobile_money_fcfa': 9876000};
  @override
  Future<List<dynamic>> soldToday() async => [
        {
          'reference': 'AX-20261107-TEST1234', 'route': 'Parakou → Cotonou (axe Savè–Glazoué–Dassa–Bohicon)', 'seat': '12A',
          'passenger_name': 'Awa-Marie-Christelle TEST AHOUANDJINOU', 'passenger_phone': '+229 01 97 00 00 12',
          'amount_fcfa': 7500, 'status_display': 'Ticket émis', 'sold_at': '2026-11-07T08:30:00Z', 'sold_by_name': 'TEST Contrôleur',
        },
      ];
}

Widget _app(Widget home, {String role = 'CLIENT'}) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_Api()),
        sessionProvider.overrideWith(() => _Session(role)),
        biometricGateProvider.overrideWithValue(_Gate()),
        appLockPrefsProvider.overrideWithValue(_Prefs()),
      ],
      child: MaterialApp(theme: AxisTheme.light(), home: home),
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final screens = <String, Widget Function()>{
    'profil client': () => _app(const Scaffold(body: ProfileScreen())),
    'mes informations': () => _app(const EditProfileScreen()),
    'e-mail et mot de passe': () => _app(const AccountScreen()),
    'paramètres de connexion': () => _app(const ConnectionSettingsScreen()),
    'à propos': () => _app(const AboutScreen(siteUrl: 'https://exemple.test')),
    'aide': () => _app(const HelpScreen()),
    'supprimer mon compte': () => _app(const DeleteAccountScreen()),
    'mot de passe obligatoire': () => _app(const ForcedPasswordScreen()),
    'recherche de trajet': () => _app(const TripSearchScreen()),
    'mes billets': () => _app(const Scaffold(body: TicketsScreen())),
    'profil du personnel': () => _app(const StaffProfileScreen(), role: 'CONTROLLER'),
    'billets vendus': () => _app(const SoldTodayScreen(), role: 'CONTROLLER'),
    'billet vendu': () => _app(const SoldTicketScreen(reference: 'AX-20261107-TEST1234'), role: 'CONTROLLER'),
  };

  // Indicateur de chargement ou rafraîchissement continus : pumpAndSettle n'aboutirait jamais.
  const continuous = {'mes billets'};

  for (final entry in screens.entries) {
    testWidgets('${entry.key} : aucun débordement', (tester) async {
      expect(await layoutOverflows(tester, entry.value, settle: !continuous.contains(entry.key)), isEmpty);
    });
  }
}
