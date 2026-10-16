import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/shell.dart';
import '../../shared/widgets.dart';
import 'sale_controller.dart';
import 'sale_models.dart';

/// Rôles autorisés à vendre. Le serveur refuse de toute façon les autres, quoi que l'écran affiche.
const sellerRoles = {'CONTROLLER', 'COUNTER', 'ADMIN'};

/// Vente d'un billet par un agent : départ, place, passager, encaissement.
class SellTicketScreen extends ConsumerStatefulWidget {
  const SellTicketScreen({super.key});

  @override
  ConsumerState<SellTicketScreen> createState() => _SellTicketScreenState();
}

class _SellTicketScreenState extends ConsumerState<SellTicketScreen>
    with WidgetsBindingObserver {
  late final SaleController _sale = SaleController(ref.read(apiClientProvider));
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sale.addListener(_refresh);
    Future.microtask(_sale.load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sale.removeListener(_refresh);
    _sale.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // Au retour de la page de paiement, on demande au serveur si le paiement est arrivé.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _sale.checkout != null &&
        (_sale.sale?.isHeld ?? false)) {
      _sale.verify();
    }
  }

  Future<void> _openPaymentPage() async {
    final url = _sale.checkout?.paymentUrl;
    if (url == null) return;
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir la page de paiement.'),
        ),
      );
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _sell() async {
    final quote = _sale.quote;
    if (quote == null) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez le nom du passager.')),
      );
      return;
    }
    if (!quote.online) {
      // Espèces : l'agent atteste avoir reçu l'argent avant que le billet soit émis.
      final received = await _confirm(
        'Espèces reçues ?',
        'Confirmez avoir reçu ${formatMoney(quote.total, quote.currency)} du passager.',
        'Oui, reçu',
      );
      if (!received) return;
    }
    await _sale.sell(passengerName: _name.text, passengerPhone: _phone.text);
    if (quote.online &&
        _sale.checkout?.paymentUrl != null &&
        (_sale.sale?.isHeld ?? false)) {
      await _openPaymentPage();
    }
  }

  Future<void> _cancel() async {
    if (await _confirm(
      'Annuler la vente ?',
      'La place sera libérée.',
      'Oui, annuler',
    )) {
      await _sale.cancel();
    }
  }

  Future<void> _newSale() async {
    _name.clear();
    _phone.clear();
    await _sale.reset();
  }

  Future<void> _share(SaleTicket ticket) {
    return Share.share(
      saleShareText(ticket, formatFullDateTime),
      subject: 'Billet AXIS Transport ${ticket.reference}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider).user?.role;
    if (!sellerRoles.contains(role)) {
      return const AxisScaffold(
        child: Notice(
          'Votre compte ne permet pas de vendre des billets.',
          error: true,
        ),
      );
    }
    final sale = _sale.sale;
    return AxisScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          const Text(
            'Vendre un billet',
            style: TextStyle(
              color: AxisColors.navyDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (_sale.loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sale != null && sale.isIssued && sale.ticket != null)
            ..._issued(sale.ticket!)
          else if (sale != null)
            ..._pending(sale)
          else
            ..._form(),
          if (_sale.error != null) Notice(_sale.error!, error: true),
        ],
      ),
    );
  }

  List<Widget> _form() {
    final trip = _sale.trip;
    final free = _sale.seats.where((item) => item.isAvailable).toList();
    return [
      if (_sale.trips.isEmpty)
        const Notice('Aucun départ vendable pour le moment.')
      else ...[
        DropdownButtonFormField<int>(
          key: const Key('sale-trip'),
          initialValue: trip?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Départ'),
          items: _sale.trips
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(
                    '${item.label} · ${item.departureAt == null ? '' : formatDateTime(item.departureAt!)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (id) =>
              _sale.selectTrip(_sale.trips.firstWhere((item) => item.id == id)),
        ),
        if (trip != null) ...[
          const SizedBox(height: 10),
          Text(
            'Places restantes : ${trip.availableSeats}'
            '${trip.boardingAt == null ? '' : ' · Embarquement : ${formatDateTime(trip.boardingAt!)}'}',
            style: const TextStyle(color: AxisColors.muted),
          ),
          if (!trip.hasFare)
            const Notice(
              'Aucun tarif n\'est défini pour ce départ : la vente est impossible.',
              error: true,
            )
          else ...[
            const SizedBox(height: 16),
            const Text('Siège', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (free.isEmpty)
              const Notice(
                'Plus aucune place libre sur ce départ.',
                error: true,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: free
                    .map(
                      (item) => ChoiceChip(
                        label: Text(item.number),
                        selected: _sale.seat?.id == item.id,
                        onSelected: (_) => _sale.selectSeat(item),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sale-passenger-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom du passager'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone du passager',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Moyen de paiement',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: trip.quotes
                  .map(
                    (item) => ChoiceChip(
                      label: Text(
                        '${item.label} · ${formatMoney(item.total, item.currency)}',
                      ),
                      selected:
                          _sale.quote?.paymentMethod == item.paymentMethod,
                      onSelected: (_) => _sale.selectQuote(item),
                    ),
                  )
                  .toList(),
            ),
            if (_sale.quote != null) ...[
              const SizedBox(height: 10),
              Text(
                'Prix du billet : ${formatMoney(_sale.quote!.amount, _sale.quote!.currency)}'
                '${_sale.quote!.feeAmount > 0 ? ' · Frais de paiement : ${formatMoney(_sale.quote!.feeAmount, _sale.quote!.currency)}' : ''}',
                style: const TextStyle(color: AxisColors.muted),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('sale-submit'),
              onPressed: _sale.canSell ? _sell : null,
              child: Text(
                _sale.busy
                    ? 'Patientez…'
                    : _sale.quote == null
                    ? 'Choisissez un moyen de paiement'
                    : _sale.quote!.online
                    ? 'Payer ${formatMoney(_sale.quote!.total, _sale.quote!.currency)} par Mobile Money'
                    : 'Encaisser ${formatMoney(_sale.quote!.total, _sale.quote!.currency)} en espèces',
              ),
            ),
          ],
        ],
      ],
      const SizedBox(height: 8),
      TextButton(
        onPressed: _sale.busy ? null : _sale.load,
        child: const Text('Actualiser les départs'),
      ),
    ];
  }

  /// Place tenue, paiement Mobile Money attendu (ou vente expirée / à rembourser).
  List<Widget> _pending(Sale sale) {
    final ticket = sale.ticket;
    final over = sale.isOver || _sale.refundDue;
    return [
      AxisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vente en cours · ${ticket?.reference ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            if (ticket != null)
              Text('${ticket.passengerName} · siège ${ticket.seatNumber}'),
            if (ticket != null)
              Text(
                ticket.routeLabel,
                style: const TextStyle(color: AxisColors.muted),
              ),
            if (_sale.checkout != null)
              Text(
                'À payer : ${formatMoney(_sale.checkout!.total, _sale.checkout!.currency)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            if (sale.isHeld && sale.expiresAt != null)
              SaleCountdown(expiresAt: sale.expiresAt!),
          ],
        ),
      ),
      if (_sale.refundDue)
        const Notice(
          'Paiement reçu après l\'expiration : aucun billet n\'a été émis. Remboursement à traiter par Axis.',
          error: true,
        )
      else if (sale.status == 'EXPIRED')
        const Notice(
          'Le délai est dépassé : la place n\'est plus tenue. Aucun billet n\'a été émis.',
          error: true,
        )
      else if (sale.status == 'CANCELLED')
        const Notice('Vente annulée. La place est libérée.')
      else
        const Notice(
          'Place tenue. Le billet sera émis dès que le serveur aura confirmé le paiement.',
        ),
      const SizedBox(height: 12),
      if (over)
        FilledButton(
          onPressed: _sale.busy ? null : _newSale,
          child: const Text('Nouvelle vente'),
        )
      else ...[
        if (_sale.checkout == null)
          // Le paiement n'a pas pu démarrer : même vente, même place, on relance seulement le paiement.
          FilledButton(
            onPressed: _sale.busy ? null : _sell,
            child: Text(_sale.busy ? 'Patientez…' : 'Réessayer le paiement'),
          )
        else ...[
          FilledButton(
            key: const Key('sale-verify'),
            onPressed: _sale.busy ? null : _sale.verify,
            child: Text(_sale.busy ? 'Vérification…' : 'Vérifier le paiement'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _sale.busy ? null : _openPaymentPage,
            child: const Text('Rouvrir la page de paiement'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sale.busy ? null : _cancel,
          child: const Text('Annuler la vente'),
        ),
      ],
    ];
  }

  List<Widget> _issued(SaleTicket ticket) {
    return [
      AxisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Billet émis · ${ticket.reference}',
              style: const TextStyle(
                color: AxisColors.success,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text('Passager : ${ticket.passengerName}'),
            Text('Siège : ${ticket.seatNumber}'),
            Text('Trajet : ${ticket.routeLabel}'),
            if (ticket.boardingAt != null)
              Text('Embarquement : ${formatFullDateTime(ticket.boardingAt!)}'),
            if (ticket.departureAt != null)
              Text('Départ : ${formatFullDateTime(ticket.departureAt!)}'),
            Text(
              'Prix du billet : ${formatMoney(ticket.amount, ticket.currency)}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('sale-share'),
        onPressed: () => _share(ticket),
        icon: const Icon(Icons.share),
        label: const Text('Partager le billet'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _newSale, child: const Text('Nouvelle vente')),
    ];
  }
}

/// Temps restant avant la libération de la place, d'après l'échéance donnée par le serveur.
class SaleCountdown extends StatefulWidget {
  const SaleCountdown({super.key, required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<SaleCountdown> createState() => _SaleCountdownState();
}

class _SaleCountdownState extends State<SaleCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    return Text(
      seconds == 0
          ? 'Délai écoulé.'
          : 'Temps restant : ${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s',
      style: const TextStyle(color: AxisColors.muted),
    );
  }
}
