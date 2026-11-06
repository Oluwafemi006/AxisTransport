import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/app_lock.dart';
import 'core/session.dart';
import 'core/theme/axis_theme.dart';
import 'router.dart';

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
  // Dernier compte connecté : à chaque changement de compte, la navigation repart de zéro.
  int? _lastUserId;

  static const _delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final userId = session.user?.id;
    if (userId != null && userId != _lastUserId) {
      if (_lastUserId != null) resetAxisRouter();
      _lastUserId = userId;
    }

    // Tant que la restauration de session est en cours, afficher un écran d'attente
    if (!session.ready) {
      return MaterialApp(
        title: 'Axis Transport',
        debugShowCheckedModeBanner: false,
        theme: AxisTheme.light(),
        locale: const Locale('fr'),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'Axis Transport',
      debugShowCheckedModeBanner: false,
      theme: AxisTheme.light(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: _delegates,
      key: ValueKey(_lastUserId),
      routerConfig: axisRouter,
      // Verrouillage par biométrie au retour au premier plan (option désactivée par défaut).
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
