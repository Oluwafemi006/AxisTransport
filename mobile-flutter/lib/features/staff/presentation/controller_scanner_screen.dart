import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_spacing.dart';
import '../../../core/theme/axis_tokens.dart';
import '../../../core/widgets/axis_button.dart';
import '../../../core/widgets/axis_text_field.dart';
import '../../../core/widgets/qr_scan_frame.dart';
import '../../../core/widgets/scan_result_sheet.dart';

/// Date et heure fournies par le serveur ; « à confirmer » si absentes.
String _serverTime(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed == null ? 'à confirmer' : formatFullDateTime(parsed.toLocal());
}

/// Lignes affichées après un scan réussi, tirées telles quelles de la réponse du serveur.
List<String> scanTicketLines(Map<String, dynamic> ticket) {
  final trip = ticket['trip_detail'] is Map
      ? ticket['trip_detail'] as Map
      : const {};
  final seat = ticket['seat_detail'] is Map
      ? ticket['seat_detail'] as Map
      : const {};
  final route = trip['route_detail'] is Map
      ? trip['route_detail'] as Map
      : const {};
  return [
    'Passager : ${ticket['passenger_name'] ?? 'à confirmer'}',
    'Siège : ${seat['number'] ?? 'à confirmer'}',
    'Trajet : ${route['label'] ?? 'à confirmer'}',
    'Embarquement : ${_serverTime(trip['boarding_at'])}',
    'Départ : ${_serverTime(trip['departure_at'])}',
  ];
}

/// Écran de scan QR contrôleur (`Scanner.html`).
class ControllerScannerScreen extends ConsumerStatefulWidget {
  const ControllerScannerScreen({
    super.key,
    this.enableCamera = true,
    this.expectedTripId,
    this.tripSubtitle,
  });

  /// Permet de désactiver le flux caméra natif dans les tests de widgets.
  final bool enableCamera;
  final int? expectedTripId;
  final String? tripSubtitle;

  @override
  ConsumerState<ControllerScannerScreen> createState() =>
      _ControllerScannerScreenState();
}

class _ControllerScannerScreenState
    extends ConsumerState<ControllerScannerScreen> {
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  bool _torchEnabled = false;

  ScanResultData? _resultData;
  String? _scannedCode;
  String? _networkError;

  @override
  void initState() {
    super.initState();
    if (widget.enableCamera) {
      _scannerController = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _resetScan() {
    setState(() {
      _isProcessing = false;
      _resultData = null;
      _scannedCode = null;
      _networkError = null;
    });
  }

  bool _isAlreadyUsedError(ApiException error) {
    final data = error.data;
    if (data is Map) {
      final result = data['result']?.toString().toUpperCase() ?? '';
      if (result.contains('ALREADY_USED')) return true;
      final rawError = data['error']?.toString().toLowerCase() ?? '';
      if (rawError.contains('déjà été contrôlé') ||
          rawError.contains('déjà scanné') ||
          rawError.contains('déjà utilisé') ||
          rawError.contains('already_used')) {
        return true;
      }
    }
    final msg = error.message.toLowerCase();
    return msg.contains('déjà été contrôlé') ||
        msg.contains('déjà scanné') ||
        msg.contains('déjà utilisé');
  }

  Future<void> _processScan(String? barcodeValue) async {
    final code = barcodeValue?.trim() ?? '';
    if (code.isEmpty || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _networkError = null;
    });

    final apiClient = ref.read(apiClientProvider);

    try {
      final response = await apiClient.validateTicket(
        code,
        expectedTripId: widget.expectedTripId,
      );
      if (!mounted) return;
      final ticket = response['ticket'] is Map
          ? Map<String, dynamic>.from(response['ticket'] as Map)
          : const <String, dynamic>{};
      final trip = ticket['trip_detail'] is Map
          ? Map<String, dynamic>.from(ticket['trip_detail'] as Map)
          : const <String, dynamic>{};
      final seat = ticket['seat_detail'] is Map
          ? Map<String, dynamic>.from(ticket['seat_detail'] as Map)
          : const <String, dynamic>{};
      final route = trip['route_detail'] is Map
          ? Map<String, dynamic>.from(trip['route_detail'] as Map)
          : const <String, dynamic>{};

      final passengerName =
          (ticket['passenger_name'] as String?)?.trim().isNotEmpty == true
              ? (ticket['passenger_name'] as String).trim()
              : 'Passager';
      final ticketNumber =
          (ticket['reference'] as String?)?.trim().isNotEmpty == true
              ? (ticket['reference'] as String).trim()
              : code;
      final seatNumber =
          (seat['number']?.toString() ?? '').trim().isNotEmpty
              ? seat['number'].toString().trim()
              : '—';
      final tripRoute =
          (route['label'] as String?)?.trim().isNotEmpty == true
              ? (route['label'] as String).trim()
              : '—';

      setState(() {
        _scannedCode = code;
        _resultData = ScanResultData(
          type: ScanResultType.valid,
          ticketNumber: ticketNumber,
          passengerName: passengerName,
          seatNumber: seatNumber,
          tripRoute: tripRoute,
        );
        _networkError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == null) {
        // Hors connexion sans liste locale des billets du trajet : message d'erreur réseau clair.
        setState(() {
          _isProcessing = false;
          _resultData = null;
          _scannedCode = code;
          _networkError =
              'Hors connexion : impossible de vérifier ce billet sans réseau. Vérifiez votre connexion et réessayez.';
        });
        return;
      }

      if (_isAlreadyUsedError(error)) {
        setState(() {
          _scannedCode = code;
          _resultData = ScanResultData(
            type: ScanResultType.alreadyUsed,
            ticketNumber: code,
            usedTimestamp: error.message,
          );
        });
      } else {
        setState(() {
          _scannedCode = code;
          _resultData = ScanResultData(
            type: ScanResultType.notFound,
            ticketNumber: code,
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _resultData = null;
        _scannedCode = code;
        _networkError =
            'Une erreur réseau est survenue lors de la vérification du billet.';
      });
    }
  }

  void _confirmBoardingAndContinue() {
    _resetScan();
  }

  Future<void> _toggleTorch() async {
    final controller = _scannerController;
    if (controller == null) {
      setState(() => _torchEnabled = !_torchEnabled);
      return;
    }
    try {
      await controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchEnabled = !_torchEnabled);
    } catch (_) {}
  }

  void _showManualInputDialog() {
    final controller = TextEditingController();
    final axis = context.axis;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AxisRadius.xl),
        ),
        title: Text(
          'Saisir le code à la main',
          style: theme.textTheme.titleMedium,
        ),
        content: AxisTextField(
          label: 'Code ou référence du billet',
          hintText: 'Ex. AX-2026-8829',
          controller: controller,
          prefixIcon: Icon(
            Icons.qr_code_rounded,
            color: axis.textSecondary,
            size: AxisSizes.icon,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Annuler',
              style: theme.textTheme.labelMedium?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(dialogContext).pop();
              if (text.isNotEmpty) {
                _resetScan();
                _processScan(text);
              }
            },
            child: Text(
              'Valider',
              style: theme.textTheme.labelMedium?.copyWith(color: axis.ink),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: axis.ink,
      body: Stack(
        children: [
          // Flux caméra en arrière-plan
          if (widget.enableCamera && _scannerController != null)
            Positioned.fill(
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: (capture) {
                  if (_isProcessing || _resultData != null) return;
                  final barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    _processScan(barcodes.first.rawValue);
                  }
                },
              ),
            ),

          // Interface superposée : barre supérieure + viseur + feuille de résultat
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Barre supérieure (retour, titre, torche)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AxisSpacing.md,
                    AxisSpacing.xs,
                    AxisSpacing.md,
                    AxisSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ScannerIconButton(
                        icon: Icons.arrow_back_rounded,
                        semanticLabel: 'Retour',
                        onTap: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            context.go('/staff');
                          }
                        },
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              'Scanner un billet',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: onDark,
                              ),
                            ),
                            if (widget.tripSubtitle != null &&
                                widget.tripSubtitle!.isNotEmpty)
                              Text(
                                widget.tripSubtitle!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: axis.borderStrong,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _ScannerIconButton(
                        icon: _torchEnabled
                            ? Icons.flashlight_on_rounded
                            : Icons.flashlight_off_rounded,
                        semanticLabel: 'Torche',
                        isActive: _torchEnabled,
                        onTap: _toggleTorch,
                      ),
                    ],
                  ),
                ),

                // Bandeau d'erreur réseau (si hors connexion sans cache local des billets du trajet)
                if (_networkError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AxisSpacing.md,
                      vertical: AxisSpacing.xs,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AxisSpacing.sm),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AxisRadius.md),
                        border: Border.all(color: axis.danger),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 16,
                                color: axis.danger,
                              ),
                              const SizedBox(width: AxisSpacing.xs),
                              Expanded(
                                child: Text(
                                  _networkError!,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: axis.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_scannedCode != null &&
                              _scannedCode!.isNotEmpty) ...[
                            const SizedBox(height: AxisSpacing.xs),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _processScan(_scannedCode),
                                child: Text(
                                  'Réessayer',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: axis.danger,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // Zone de visée centrale (QrScanFrame)
                const Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: ClampingScrollPhysics(),
                      child: QrScanFrame(
                        boxSize: 196,
                        instruction: 'Placez le QR code du billet dans le cadre',
                        animateLaser: false,
                      ),
                    ),
                  ),
                ),

                // Feuille basse : résultat du scan (3 états) ou état d'attente + saisie manuelle
                if (_resultData != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.56,
                    ),
                    child: SingleChildScrollView(
                      child: ScanResultSheet(
                        data: _resultData!,
                        onPrimaryAction: switch (_resultData!.type) {
                          ScanResultType.valid => _confirmBoardingAndContinue,
                          ScanResultType.alreadyUsed => _resetScan,
                          ScanResultType.notFound => () {
                            _resetScan();
                            context.go('/vendre');
                          },
                        },
                        onSecondaryAction: _resetScan,
                        onManualInput: _showManualInputDialog,
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      AxisSpacing.lg,
                      AxisSpacing.md,
                      AxisSpacing.lg,
                      AxisSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AxisRadius.xl),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: axis.border,
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.pill,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AxisSpacing.md),
                          Text(
                            _isProcessing
                                ? 'Vérification du billet en cours…'
                                : 'Prêt à scanner un billet',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: AxisSpacing.xs),
                          Text(
                            'Présentez le QR code du passager ou saisissez la référence manuellement.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: axis.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AxisSpacing.md),
                          AxisButton(
                            label: 'Saisir le code à la main',
                            variant: AxisButtonVariant.ghost,
                            icon: const Icon(Icons.keyboard_alt_outlined),
                            onPressed: _showManualInputDialog,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerIconButton extends StatelessWidget {
  const _ScannerIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final onDark = Theme.of(context).colorScheme.onPrimary;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: isActive
            ? axis.accent.withValues(alpha: 0.24)
            : onDark.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AxisRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AxisRadius.md),
          onTap: onTap,
          child: SizedBox(
            width: AxisSizes.minTarget,
            height: AxisSizes.minTarget,
            child: Icon(
              icon,
              size: AxisSizes.icon,
              color: isActive ? axis.accent : onDark,
            ),
          ),
        ),
      ),
    );
  }
}
