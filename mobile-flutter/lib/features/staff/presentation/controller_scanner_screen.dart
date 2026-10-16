import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/formatters.dart';
import '../../../core/session.dart';

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

class ControllerScannerScreen extends ConsumerStatefulWidget {
  const ControllerScannerScreen({super.key});

  @override
  ConsumerState<ControllerScannerScreen> createState() =>
      _ControllerScannerScreenState();
}

class _ControllerScannerScreenState
    extends ConsumerState<ControllerScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _processScan(String? barcodeValue) async {
    if (barcodeValue == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final apiClient = ref.read(apiClientProvider);

    try {
      final response = await apiClient.validateTicket(barcodeValue);
      if (mounted) {
        _showResultModal(
          success: true,
          message: response['message'] ?? 'Billet validé.',
          ticketData: response['ticket'] as Map<String, dynamic>?,
        );
      }
    } catch (e) {
      if (mounted) {
        _showResultModal(
          success: false,
          message: e.toString(),
          ticketData: null,
        );
      }
    }
  }

  void _showResultModal({
    required bool success,
    required String message,
    required Map<String, dynamic>? ticketData,
  }) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: success ? Colors.green : Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  success ? 'Succès' : 'Échec',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: success ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (success && ticketData != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  for (final (index, line) in scanTicketLines(
                    ticketData,
                  ).indexed)
                    Text(
                      line,
                      style: index == 0
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _isProcessing = false;
                    });
                  },
                  child: const Text('Scanner le suivant'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showManualInputDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saisie manuelle du code'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Entrez le code ou token du billet',
            prefixIcon: Icon(Icons.qr_code),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(context).pop();
              if (text.isNotEmpty) {
                _processScan(text);
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrôle des Billets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Saisie manuelle',
            onPressed: _showManualInputDialog,
          ),
          IconButton(
            icon: const Icon(Icons.flashlight_on, color: Colors.yellow),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                _processScan(barcodes.first.rawValue);
              }
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Placez le QR Code du billet dans le cadre pour le scanner et valider l\'embarquement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
