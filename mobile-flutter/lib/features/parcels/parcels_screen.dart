import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Suivi de colis. Le client ne crée jamais de colis : l'agence l'enregistre
/// et remet un code de suivi, que le client saisit ici.
class ParcelsScreen extends ConsumerStatefulWidget {
  const ParcelsScreen({super.key});

  @override
  ConsumerState<ParcelsScreen> createState() => _ParcelsScreenState();
}

class _ParcelsScreenState extends ConsumerState<ParcelsScreen> {
  final _code = TextEditingController();
  ParcelTracking? _tracking;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _tracking = null;
    });
    try {
      final tracking = await ref.read(apiClientProvider).trackParcel(code);
      if (mounted) setState(() => _tracking = tracking);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = _tracking;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
      children: [
        const Text(
          'Suivi de colis',
          style: TextStyle(
            color: AxisColors.navyDark,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Votre colis est enregistré en agence. Saisissez le code de suivi qui vous a été remis.',
          style: TextStyle(color: AxisColors.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        AxisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _code,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _track(),
                decoration: const InputDecoration(
                  labelText: 'Code de suivi',
                  hintText: 'AX-COL-…',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _track,
                icon: const Icon(Icons.search),
                label: Text(_busy ? 'Recherche…' : 'Suivre mon colis'),
              ),
            ],
          ),
        ),
        if (_error != null) Notice(_error!, error: true),
        if (tracking != null) ...[
          const SizedBox(height: 16),
          AxisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracking.trackingNumber,
                  style: const TextStyle(color: AxisColors.muted, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${tracking.origin} → ${tracking.destination}',
                  style: const TextStyle(
                    color: AxisColors.navyDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                for (final step in tracking.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          step.done ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: step.done ? AxisColors.success : AxisColors.muted,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step.label,
                            style: TextStyle(
                              color: step.done ? AxisColors.text : AxisColors.muted,
                              fontWeight: step.current ? FontWeight.w900 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (step.reachedAt != null)
                          Text(
                            formatDateTime(step.reachedAt!),
                            style: const TextStyle(color: AxisColors.muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
