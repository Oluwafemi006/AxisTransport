import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'session.dart';

/// Délai passé en arrière-plan au-delà duquel l'application se verrouille (si l'option est activée).
const appLockDelay = Duration(minutes: 2);

/// Accès à la biométrie du téléphone. Aucun mot de passe n'est lu, stocké ni transmis :
/// le téléphone répond seulement « reconnu » ou « non reconnu ».
abstract class BiometricGate {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class LocalAuthGate implements BiometricGate {
  LocalAuthGate([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      // Biométrie indisponible, bloquée, annulée ou modifiée : traité comme un échec.
      return false;
    }
  }
}

/// Préférence « déverrouiller avec la biométrie », gardée sur le téléphone (stockage sécurisé).
abstract class AppLockPrefs {
  Future<bool> read();
  Future<void> write(bool enabled);
}

class SecureAppLockPrefs implements AppLockPrefs {
  static const _key = 'axis_app_lock_biometric';
  final _storage = const FlutterSecureStorage();

  @override
  Future<bool> read() async {
    try {
      return await _storage.read(key: _key) == 'on';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> write(bool enabled) async {
    try {
      await _storage.write(key: _key, value: enabled ? 'on' : 'off');
    } catch (_) {}
  }
}

final biometricGateProvider = Provider<BiometricGate>((ref) => LocalAuthGate());
final appLockPrefsProvider = Provider<AppLockPrefs>((ref) => SecureAppLockPrefs());

class AppLockState {
  const AppLockState({this.enabled = false, this.locked = false});
  final bool enabled;
  final bool locked;
}

class AppLockController extends Notifier<AppLockState> {
  DateTime? _pausedAt;

  @override
  AppLockState build() {
    Future.microtask(_load);
    return const AppLockState();
  }

  Future<void> _load() async {
    final enabled = await ref.read(appLockPrefsProvider).read();
    state = AppLockState(enabled: enabled, locked: state.locked);
  }

  /// Activation : seulement si la biométrie est disponible ET reconnue une première fois.
  Future<String?> enable() async {
    final gate = ref.read(biometricGateProvider);
    if (!await gate.available()) {
      return 'Aucune empreinte ou biométrie n’est disponible sur ce téléphone.';
    }
    if (!await gate.authenticate('Confirmez pour activer le déverrouillage')) {
      return 'Biométrie non reconnue : l’option reste désactivée.';
    }
    await ref.read(appLockPrefsProvider).write(true);
    state = const AppLockState(enabled: true);
    return null;
  }

  Future<void> disable() async {
    await ref.read(appLockPrefsProvider).write(false);
    state = const AppLockState(enabled: false);
  }

  void paused(DateTime at) => _pausedAt = at;

  /// Retour au premier plan : verrouille si l'option est active, un compte connecté et le délai dépassé.
  void resumed(DateTime at) {
    final since = _pausedAt;
    _pausedAt = null;
    final loggedIn = ref.read(sessionProvider).user != null;
    if (state.enabled && loggedIn && since != null && at.difference(since) >= appLockDelay) {
      state = AppLockState(enabled: true, locked: true);
    }
  }

  Future<bool> unlock() async {
    final ok = await ref.read(biometricGateProvider).authenticate('Déverrouillez Axis Transport');
    if (ok) state = AppLockState(enabled: state.enabled);
    return ok;
  }

  /// Échec ou biométrie indisponible : retour à la connexion par mot de passe.
  Future<void> usePassword() async {
    state = AppLockState(enabled: state.enabled);
    await ref.read(sessionProvider.notifier).logout();
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

/// Enveloppe de l'application : observe le passage en arrière-plan et affiche l'écran de verrouillage.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) lock.paused(DateTime.now());
    if (state == AppLifecycleState.resumed) lock.resumed(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(children: [widget.child, if (locked) const Positioned.fill(child: AppLockScreen())]);
  }
}

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_unlock);
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(appLockProvider.notifier).unlock();
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fingerprint, size: 64),
                const SizedBox(height: 16),
                Text('Application verrouillée', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  _failed
                      ? 'Biométrie non reconnue ou indisponible. Réessayez, ou reconnectez-vous avec votre mot de passe.'
                      : 'Déverrouillez avec votre empreinte ou votre biométrie.',
                  key: const Key('app-lock-message'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('app-lock-retry'),
                  onPressed: _busy ? null : _unlock,
                  child: const Text('Déverrouiller'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('app-lock-password'),
                  onPressed: _busy ? null : () => ref.read(appLockProvider.notifier).usePassword(),
                  child: const Text('Se connecter avec le mot de passe'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
