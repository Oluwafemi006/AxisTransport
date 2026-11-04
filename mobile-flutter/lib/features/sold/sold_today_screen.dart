import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_header.dart';
import 'sold_ticket.dart';

/// Liste chargée depuis le serveur : elle ne dépend d'aucun état en mémoire.
final soldTodayProvider = FutureProvider.autoDispose<List<SoldTicket>>((ref) async {
  final rows = await ref.read(apiClientProvider).soldToday();
  return rows.whereType<Map<String, dynamic>>().map(SoldTicket.fromJson).toList();
});

// Dernier billet ouvert : au retour de WhatsApp, si Android a fermé l'application, on le rouvre.
const _lastKey = 'axis_last_sold_ticket';
const _storage = FlutterSecureStorage();

Future<void> _remember(String reference) async {
  try {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    await _storage.write(key: _lastKey, value: '$day|$reference');
  } catch (_) {}
}

Future<String?> _lastOpenedToday() async {
  try {
    final value = await _storage.read(key: _lastKey);
    if (value == null) return null;
    final parts = value.split('|');
    final day = DateTime.now().toIso8601String().substring(0, 10);
    return parts.length == 2 && parts[0] == day ? parts[1] : null;
  } catch (_) {
    return null;
  }
}

String _time(DateTime? at) => at == null
    ? ''
    : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

class SoldTodayScreen extends ConsumerStatefulWidget {
  const SoldTodayScreen({super.key, this.reopenLast = true});

  /// Faux dans les tests : pas de stockage sécurisé hors téléphone.
  final bool reopenLast;

  @override
  ConsumerState<SoldTodayScreen> createState() => _SoldTodayScreenState();
}

class _SoldTodayScreenState extends ConsumerState<SoldTodayScreen> {
  static bool _reopened = false;

  @override
  void initState() {
    super.initState();
    if (widget.reopenLast && !_reopened) {
      _reopened = true;
      Future.microtask(() async {
        final reference = await _lastOpenedToday();
        if (reference != null && mounted) context.push('/vendus/${Uri.encodeComponent(reference)}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final rows = ref.watch(soldTodayProvider);
    return Scaffold(
      body: Column(
        children: [
          const AxisHeader(
            variant: AxisHeaderVariant.controller,
            title: 'Billets vendus aujourd’hui',
            subtitle: 'Ouvrir ou renvoyer un billet',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(soldTodayProvider.future),
              child: rows.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => ListView(
                  padding: const EdgeInsets.all(AxisSpacing.lg),
                  children: [
                    const Text('La liste n’a pas pu être chargée. Vérifiez la connexion.'),
                    const SizedBox(height: AxisSpacing.md),
                    AxisButton(
                      label: 'Réessayer',
                      variant: AxisButtonVariant.outline,
                      onPressed: () => ref.invalidate(soldTodayProvider),
                    ),
                  ],
                ),
                data: (tickets) => tickets.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(AxisSpacing.lg),
                        children: const [Text('Aucun billet vendu aujourd’hui.')],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AxisSpacing.md),
                        itemCount: tickets.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AxisSpacing.xs),
                        itemBuilder: (context, index) {
                          final ticket = tickets[index];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              key: Key('sold-${ticket.reference}'),
                              title: Text(
                                '${ticket.passengerName} · Siège ${ticket.seat}',
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                '${ticket.route}\n${ticket.reference}\n'
                                '${formatFcfa(ticket.amountFcfa)} · ${ticket.statusDisplay} · ${_time(ticket.soldAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: axis.textSecondary),
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/vendus/${Uri.encodeComponent(ticket.reference)}'),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Écran d'un billet vendu : rechargé depuis le serveur par sa référence, donc jamais perdu.
class SoldTicketScreen extends ConsumerStatefulWidget {
  const SoldTicketScreen({super.key, required this.reference});

  final String reference;

  @override
  ConsumerState<SoldTicketScreen> createState() => _SoldTicketScreenState();
}

class _SoldTicketScreenState extends ConsumerState<SoldTicketScreen> {
  @override
  void initState() {
    super.initState();
    _remember(widget.reference);
  }

  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le lien. Utilisez « Partager le lien ».')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = ref.watch(soldTodayProvider);
    return Scaffold(
      body: Column(
        children: [
          AxisHeader(
            variant: AxisHeaderVariant.controller,
            title: 'Billet ${widget.reference}',
            onBack: () => context.canPop() ? context.pop() : context.go('/vendus'),
          ),
          Expanded(
            child: rows.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: AxisButton(
                  label: 'Réessayer',
                  variant: AxisButtonVariant.outline,
                  expanded: false,
                  onPressed: () => ref.invalidate(soldTodayProvider),
                ),
              ),
              data: (tickets) {
                final ticket = tickets.where((t) => t.reference == widget.reference).firstOrNull;
                if (ticket == null) {
                  return const Padding(
                    padding: EdgeInsets.all(AxisSpacing.lg),
                    child: Text('Ce billet ne fait pas partie de vos ventes du jour.'),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(AxisSpacing.lg),
                  children: [
                    Text(ticket.passengerName, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AxisSpacing.xs),
                    Text('${ticket.route} · Siège ${ticket.seat}'),
                    Text('${formatFcfa(ticket.amountFcfa)} · ${ticket.statusDisplay} · vendu à ${_time(ticket.soldAt)}'),
                    if (ticket.passengerPhone.isNotEmpty) Text('Téléphone : ${ticket.passengerPhone}'),
                    const SizedBox(height: AxisSpacing.lg),
                    AxisButton(
                      key: const Key('sold-whatsapp'),
                      label: 'Envoyer par WhatsApp',
                      icon: const Icon(Icons.chat),
                      onPressed: () => _open(whatsappTicketUri(ticket)),
                    ),
                    const SizedBox(height: AxisSpacing.sm),
                    AxisButton(
                      label: 'Partager le lien',
                      variant: AxisButtonVariant.outline,
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => SharePlus.instance.share(ShareParams(text: ticket.message)),
                    ),
                    if (ticket.publicUrl.isNotEmpty) ...[
                      const SizedBox(height: AxisSpacing.sm),
                      AxisButton(
                        label: 'Ouvrir le billet',
                        variant: AxisButtonVariant.outline,
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => _open(Uri.parse(ticket.publicUrl)),
                      ),
                      const SizedBox(height: AxisSpacing.sm),
                      AxisButton(
                        label: 'Copier le lien',
                        variant: AxisButtonVariant.ghost,
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: ticket.publicUrl));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié.')));
                          }
                        },
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: AxisSpacing.sm),
                        child: Text('Adresse du site : à renseigner sur le serveur (lien du billet indisponible).'),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
