import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.ticketId, this.initialTicket});

  final int ticketId;
  final Ticket? initialTicket;

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  Ticket? _ticket;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ticket = widget.initialTicket;
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final cached = await api.store.findCachedTicket(widget.ticketId);
      if (mounted && cached != null) {
        setState(() {
          _ticket = cached;
          _loading = false;
        });
      } else if (mounted && _ticket != null) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted && _ticket != null) setState(() => _loading = false);
    }

    try {
      final user = await api.me();
      if (user.isClient) {
        await api.store.setActiveClient(user.id);
        final tickets = await api.tickets();
        await api.store.cacheTickets(tickets);
        final current = tickets
            .where((item) => item.id == widget.ticketId)
            .firstOrNull;
        if (mounted) setState(() => _ticket = current);
      }
    } catch (_) {
      // The locally issued ticket stays readable without a network connection.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareTicket(Ticket ticket) async {
    const domain = 'https://axis.bj';
    final publicUrl = '$domain/t/${ticket.reference}';
    final amountText = formatMoney(ticket.amount, ticket.currency);

    final text = '''
AXIS Transport 🚌

Votre billet est confirmé.

🎫 Billet : ${ticket.reference}
💺 Siège : ${ticket.seat.number}
💰 Montant : $amountText

Consultez votre billet :
$publicUrl

Merci de voyager avec AXIS Transport.''';

    await Share.share(text, subject: 'Billet AXIS Transport ${ticket.reference}');
  }

  @override
  Widget build(BuildContext context) {
    final item = _ticket;
    final canShowQr = item?.isConfirmed == true && item!.qrToken.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billet électronique'),
        actions: [
          if (item != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Partager le billet',
              onPressed: () => _shareTicket(item),
            ),
        ],
      ),
      body: _loading && item == null
          ? const Center(child: CircularProgressIndicator())
          : item == null
          ? const Center(child: Text('Billet introuvable.'))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AxisColors.navyDark,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.trip.route.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: canShowQr
                                  ? AxisColors.success
                                  : AxisColors.warning,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              item.statusDisplay,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatFullDateTime(item.trip.departureAt),
                        style: const TextStyle(color: Color(0xFFCBE0F6)),
                      ),
                      const SizedBox(height: 24),
                      if (canShowQr)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: PrettyQrView.data(data: item.qrToken),
                          ),
                        )
                      else
                        const Text(
                          'Le QR sera disponible après confirmation du billet.',
                          style: TextStyle(color: Colors.white),
                        ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          item.reference,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Divider(height: 34, color: Color(0xFF31577D)),
                      Text(
                        'Passager : ${item.passengerName}',
                        style: const TextStyle(color: Color(0xFFE2ECF7)),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Siège : ${item.seat.number}',
                        style: const TextStyle(color: Color(0xFFE2ECF7)),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Montant : ${formatMoney(item.amount, item.currency)}',
                        style: const TextStyle(color: Color(0xFFE2ECF7)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _shareTicket(item),
                  icon: const Icon(Icons.share),
                  label: const Text('Partager le billet'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (canShowQr) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Billet enregistré sur ce téléphone et consultable hors connexion. Présentez ce QR code à l’embarquement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AxisColors.muted, height: 1.45),
                  ),
                ],
              ],
            ),
    );
  }
}
