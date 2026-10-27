import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/session.dart';
import 'core/theme/axis_theme.dart';
import 'features/auth/login_screen.dart';
import 'router.dart';
import 'staff_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');
  runApp(const ProviderScope(child: AxisTransportApp()));
}

class AxisTransportApp extends ConsumerStatefulWidget {
  const AxisTransportApp({super.key});

  @override
  ConsumerState<AxisTransportApp> createState() => _AxisTransportAppState();
}

class _AxisTransportAppState extends ConsumerState<AxisTransportApp> {
  // Navigation du personnel, recréée à chaque connexion d'un agent (aucun écran d'un compte précédent).
  GoRouter? _staffRouter;
  int? _staffUserId;

  static const _delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // Connexion ou inscription obligatoire avant toute action : tant qu'aucun client
    // n'est connecté, aucune autre page de l'application n'est accessible.
    if (session.user == null) {
      return MaterialApp(
        title: 'Axis Transport',
        debugShowCheckedModeBanner: false,
        theme: AxisTheme.light(),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: _delegates,
        home: session.ready
            ? const LoginScreen(required: true)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    // L'interface dépend uniquement du rôle renvoyé par le serveur : un client n'a jamais
    // accès à la navigation du personnel, et inversement.
    final user = session.user!;
    final GoRouter router;
    if (user.isStaff) {
      if (_staffRouter == null || _staffUserId != user.id) {
        _staffRouter = buildStaffRouter();
        _staffUserId = user.id;
      }
      router = _staffRouter!;
    } else {
      router = axisRouter;
    }
    return MaterialApp.router(
      key: ValueKey(user.isStaff ? 'personnel' : 'client'),
      title: 'Axis Transport',
      debugShowCheckedModeBanner: false,
      theme: AxisTheme.light(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: _delegates,
      routerConfig: router,
    );
  }
}
