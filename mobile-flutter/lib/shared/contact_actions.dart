import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/session.dart';
import 'widgets.dart';

final contactProvider = FutureProvider<Map<String, String>>((ref) {
  return ref.watch(apiClientProvider).contact();
});

/// Boutons Appeler / WhatsApp. Rien n'est affiché tant que l'administrateur
/// n'a pas renseigné les numéros : aucun numéro n'est codé dans l'application.
class ContactActions extends ConsumerWidget {
  const ContactActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactProvider).value;
    final phone = contact?['phone'] ?? '';
    final whatsapp = contact?['whatsapp'] ?? '';
    if (phone.isEmpty && whatsapp.isEmpty) return const SizedBox.shrink();

    return AxisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Contacter Axis', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (phone.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^+0-9]'), ''))),
              icon: const Icon(Icons.call),
              label: const Text('Appeler'),
            ),
          if (phone.isNotEmpty && whatsapp.isNotEmpty) const SizedBox(height: 8),
          if (whatsapp.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
            ),
        ],
      ),
    );
  }
}
