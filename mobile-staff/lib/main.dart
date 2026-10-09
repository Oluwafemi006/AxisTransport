import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');
  runApp(const ProviderScope(child: AxisTransportApp()));
}

class AxisTransportApp extends ConsumerWidget {
  const AxisTransportApp({super.key});

  static const _delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    // Connexion obligatoire : tant qu'aucun membre du personnel n'est connecté,
    // aucune autre page de l'application n'est accessible.
    if (session.user == null) {
      return MaterialApp(
        title: 'Axis Transport',
        debugShowCheckedModeBanner: false,
        theme: axisTheme(),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: _delegates,
        home: session.ready
            ? const LoginScreen()
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp.router(
      title: 'Axis Transport',
      debugShowCheckedModeBanner: false,
      theme: axisTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: _delegates,
      routerConfig: axisRouter,
    );
  }
}
