import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/theme/axis_typography.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_header.dart';
import '../../core/widgets/axis_text_field.dart';
import '../../core/widgets/choice_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/segmented_toggle.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../shared/payment_link.dart';
import 'sale_controller.dart';
import 'sale_models.dart';

/// Rôles autorisés à vendre. Le serveur refuse de toute façon les autres, quoi que l'écran affiche.
const sellerRoles = {'CONTROLLER', 'COUNTER', 'ADMIN'};

/// Vente d'un billet par un agent (`Vente.html` & `VenteOk.html`).
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
    Future.microtask(_loadInitialSale);
  }

  Future<void> _loadInitialSale() async {
    await _sale.load();
    if (_sale.trip == null && _sale.trips.isNotEmpty) {
      await _selectTripWithDefaultQuote(_sale.trips.first);
    }
  }

  Future<void> _selectTripWithDefaultQuote(SaleTrip selected) async {
    await _sale.selectTrip(selected);
    if (_sale.quote == null && selected.quotes.isNotEmpty) {
      final cashQuote =
          selected.quotes.where((q) => !q.online).firstOrNull ??
          selected.quotes.first;
      _sale.selectQuote(cashQuote);
    }
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
    final opened = await openPaymentPage(Uri.parse(url));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir la page de paiement.'),
        ),
      );
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final axis = context.axis;
    final theme = Theme.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AxisRadius.xl),
        ),
        title: Text(title, style: theme.textTheme.titleMedium),
        content: Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: axis.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Non',
              style: theme.textTheme.labelMedium?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              yes,
              style: theme.textTheme.labelMedium?.copyWith(color: axis.ink),
            ),
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
        'Confirmez avoir reçu ${formatMoney(quote.amount, quote.currency)} du passager.',
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
    return SharePlus.instance.share(
      ShareParams(
        text: saleShareText(ticket, formatFullDateTime),
        subject: 'Billet AXIS Transport ${ticket.reference}',
      ),
    );
  }

  Future<void> _sendSms(SaleTicket ticket) async {
    final body = saleShareText(ticket, formatFullDateTime);
    final phone = _phone.text.trim();
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: <String, String>{'body': body},
    );
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        await _share(ticket);
      }
    } catch (_) {
      await _share(ticket);
    }
  }

  void _showQrModal(SaleTicket ticket) {
    final axis = context.axis;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AxisRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AxisSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'QR Code du billet',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AxisSpacing.xs),
              Text(
                ticket.reference,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: axis.textSecondary,
                ),
              ),
              const SizedBox(height: AxisSpacing.md),
              Container(
                width: 196,
                height: 196,
                padding: const EdgeInsets.all(AxisSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AxisRadius.lg),
                  border: Border.all(color: axis.border),
                ),
                child: PrettyQrView.data(data: ticket.reference),
              ),
              const SizedBox(height: AxisSpacing.sm),
              Text(
                '${ticket.passengerName} · Siège ${ticket.seatNumber}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AxisSpacing.md),
              AxisButton(
                label: 'Fermer',
                variant: AxisButtonVariant.secondary,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectPaymentMode(int index, SaleTrip trip) {
    if (index == 0) {
      final cashQuote = trip.quotes.where((q) => !q.online).firstOrNull ??
          (trip.quotes.isNotEmpty ? trip.quotes.first : null);
      if (cashQuote != null) _sale.selectQuote(cashQuote);
    } else {
      final onlineQuote = trip.quotes.where((q) => q.online).firstOrNull ??
          (trip.quotes.length > 1 ? trip.quotes[1] : null);
      if (onlineQuote != null) _sale.selectQuote(onlineQuote);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = ref.watch(sessionProvider).user?.role;
    if (!sellerRoles.contains(role)) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Column(
          children: [
            AxisHeader(
              variant: AxisHeaderVariant.controller,
              title: 'Vendre un billet',
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Accès non autorisé',
                description:
                    'Votre compte ne permet pas de vendre des billets.',
              ),
            ),
          ],
        ),
      );
    }

    final sale = _sale.sale;
    if (sale != null && sale.isIssued && sale.ticket != null) {
      return _buildIssuedView(context, sale.ticket!);
    }

    final trip = _sale.trip;
    final subtitle = trip != null
        ? 'En route · Départ ${trip.label}'
        : 'Sélectionnez un départ et un siège';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AxisHeader(
            variant: AxisHeaderVariant.controller,
            title: 'Vendre un billet',
            subtitle: subtitle,
            onBack: Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(
            child: _sale.loading
                ? ListView(
                    padding: const EdgeInsets.all(AxisSpacing.md),
                    children: const [
                      SkeletonBox(height: 68),
                      SizedBox(height: AxisSpacing.sm),
                      SkeletonBox(height: 68),
                      SizedBox(height: AxisSpacing.md),
                      SkeletonBox(height: 110),
                      SizedBox(height: AxisSpacing.md),
                      SkeletonBox(height: 120),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(AxisSpacing.md),
                    children: [
                      if (_sale.error != null) ...[
                        _ErrorBanner(message: _sale.error!),
                        const SizedBox(height: AxisSpacing.md),
                      ],
                      if (sale != null)
                        ..._pending(context, sale)
                      else
                        ..._form(context),
                    ],
                  ),
          ),
          if (!_sale.loading && sale == null && trip != null && trip.hasFare)
            _buildBottomBar(context, trip),
        ],
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final trip = _sale.trip;
    final free = _sale.seats.where((item) => item.isAvailable).toList();

    if (_sale.trips.isEmpty) {
      return [
        EmptyState(
          icon: Icons.directions_bus_outlined,
          title: 'Aucun départ vendable pour le moment.',
          description:
              'Vérifiez que des trajets sont programmés aujourd’hui ou actualisez la liste.',
          actionLabel: 'Actualiser les départs',
          onAction: _sale.busy ? null : _sale.load,
        ),
      ];
    }

    final cashQuote = trip?.quotes.where((q) => !q.online).firstOrNull;
    final onlineQuote = trip?.quotes.where((q) => q.online).firstOrNull;
    final isOnlineSelected = _sale.quote?.online ?? false;

    return [
      Text(
        'DESTINATION (DEPUIS L’ARRÊT ACTUEL)',
        style: theme.textTheme.labelSmall?.copyWith(
          color: axis.textSecondary,
          letterSpacing: 0.7,
        ),
      ),
      const SizedBox(height: AxisSpacing.xs),
      for (final item in _sale.trips) ...[
        ChoiceCard(
          key: item.id == trip?.id ? const Key('sale-trip') : null,
          tone: ChoiceCardTone.ink,
          selected: item.id == trip?.id,
          onTap: () => _selectTripWithDefaultQuote(item),
          title: item.label,
          subtitle:
              '${item.availableSeats} places libres'
              '${item.departureAt != null ? ' · Départ ${formatTime(item.departureAt!)}' : ''}',
          price: item.quotes.isNotEmpty
              ? formatMoney(
                  item.quotes.first.amount,
                  item.quotes.first.currency,
                )
              : 'Tarif absent',
        ),
        const SizedBox(height: AxisSpacing.xs),
      ],

      if (trip != null) ...[
        if (!trip.hasFare) ...[
          const SizedBox(height: AxisSpacing.sm),
          const _ErrorBanner(
            message:
                'Aucun tarif n\'est défini pour ce départ : la vente est impossible.',
          ),
        ] else ...[
          if (trip.originBoardingPoints.isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.md),
            DropdownButtonFormField<int>(
              initialValue: _sale.boardingPointId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Embarquement (${trip.originName})',
              ),
              items: trip.originBoardingPoints
                  .map(
                    (p) => DropdownMenuItem<int>(
                      value: p.id,
                      child: Text(p.name),
                    ),
                  )
                  .toList(),
              onChanged: _sale.selectBoardingPoint,
            ),
          ],
          if (trip.destinationBoardingPoints.isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: _sale.alightingPointId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Débarquement (${trip.destinationName})',
              ),
              items: trip.destinationBoardingPoints
                  .map(
                    (p) => DropdownMenuItem<int>(
                      value: p.id,
                      child: Text(p.name),
                    ),
                  )
                  .toList(),
              onChanged: _sale.selectAlightingPoint,
            ),
          ],

          const SizedBox(height: AxisSpacing.md),
          Text(
            'SIÈGE LIBRE SUR CE TRONÇON',
            style: theme.textTheme.labelSmall?.copyWith(
              color: axis.textSecondary,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: AxisSpacing.xs),
          if (free.isEmpty)
            const _ErrorBanner(
              message: 'Plus aucune place libre sur ce départ.',
            )
          else
            Wrap(
              spacing: AxisSpacing.xs,
              runSpacing: AxisSpacing.xs,
              children: _sale.seats.map((item) {
                final selected = _sale.seat?.id == item.id;
                final available = item.isAvailable;
                return InkWell(
                  borderRadius: BorderRadius.circular(AxisRadius.md),
                  onTap: available ? () => _sale.selectSeat(item) : null,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 52,
                      minHeight: AxisSizes.minTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AxisSpacing.sm,
                      vertical: AxisSpacing.xs,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? axis.ink
                          : available
                              ? theme.colorScheme.surface
                              : axis.surfaceSoft,
                      borderRadius: BorderRadius.circular(AxisRadius.md),
                      border: Border.all(
                        color: selected ? axis.ink : axis.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      available
                          ? item.number
                          : item.status == 'HELD'
                              ? '${item.number} · Retenu'
                              : '${item.number} · Occupé',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected
                            ? axis.accent
                            : available
                                ? axis.ink
                                : axis.textMuted,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: AxisSpacing.md),
          Text(
            'PASSAGER',
            style: theme.textTheme.labelSmall?.copyWith(
              color: axis.textSecondary,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: AxisSpacing.xs),
          Container(
            padding: const EdgeInsets.all(AxisSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AxisRadius.lg),
              border: Border.all(color: axis.border),
            ),
            child: Column(
              children: [
                AxisTextField(
                  key: const Key('sale-passenger-name'),
                  label: 'Nom complet *',
                  hintText: 'Ex. Kossi Mensah',
                  controller: _name,
                ),
                const SizedBox(height: AxisSpacing.sm),
                AxisTextField(
                  label: 'Téléphone *',
                  hintText: '+229 01 ·· ·· ·· ··',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),

          const SizedBox(height: AxisSpacing.md),
          Text(
            'PAIEMENT REÇU',
            style: theme.textTheme.labelSmall?.copyWith(
              color: axis.textSecondary,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: AxisSpacing.xs),
          SegmentedToggle<int>(
            options: const [
              SegmentOption(value: 0, label: 'Espèces'),
              SegmentOption(value: 1, label: 'Mobile Money'),
            ],
            selectedValue: isOnlineSelected ? 1 : 0,
            onChanged: (idx) {
              if (idx == 0 && cashQuote != null) {
                _sale.selectQuote(cashQuote);
              } else if (idx == 1 && onlineQuote != null) {
                _sale.selectQuote(onlineQuote);
              } else {
                _selectPaymentMode(idx, trip);
              }
            },
          ),
          const SizedBox(height: AxisSpacing.xs),
          Text(
            isOnlineSelected
                ? 'Une demande de paiement sera envoyée au téléphone du passager. Le billet sera émis dès confirmation.'
                : 'Encaissez le montant exact avant de valider. Il sera ajouté aux espèces à remettre en fin de journée.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: axis.textSecondary,
            ),
          ),
        ],
      ],
      const SizedBox(height: AxisSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _sale.busy ? null : _sale.load,
          icon: Icon(Icons.refresh_rounded, size: 18, color: axis.ink),
          label: Text(
            'Actualiser les départs',
            style: theme.textTheme.labelMedium?.copyWith(color: axis.ink),
          ),
        ),
      ),
    ];
  }

  Widget _buildBottomBar(BuildContext context, SaleTrip trip) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final quote = _sale.quote;
    final amountLabel = quote != null
        ? formatMoney(quote.amount, quote.currency)
        : '—';

    final buttonLabel = _sale.busy
        ? 'Patientez…'
        : quote == null
            ? 'Choisissez un moyen de paiement'
            : quote.online
                ? 'Demander le paiement de $amountLabel'
                : 'Encaisser $amountLabel';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AxisSpacing.lg,
        AxisSpacing.sm,
        AxisSpacing.lg,
        AxisSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: axis.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: axis.textSecondary,
                  ),
                ),
                Text(
                  amountLabel,
                  style: AxisTypography.price.copyWith(color: axis.ink),
                ),
              ],
            ),
            const SizedBox(height: AxisSpacing.xs),
            AxisButton(
              key: const Key('sale-submit'),
              label: buttonLabel,
              textColor: AxisButtonTextColor.ink,
              loading: _sale.busy,
              onPressed: _sale.canSell ? _sell : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Place tenue, paiement Mobile Money attendu (ou vente expirée / à rembourser).
  List<Widget> _pending(BuildContext context, Sale sale) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final ticket = sale.ticket;
    final over = sale.isOver || _sale.refundDue;

    return [
      Container(
        padding: const EdgeInsets.all(AxisSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AxisRadius.lg),
          border: Border.all(color: axis.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vente en cours · ${ticket?.reference ?? ''}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AxisSpacing.xs),
            if (ticket != null)
              Text(
                '${ticket.passengerName} · siège ${ticket.seatNumber}',
                style: theme.textTheme.bodyMedium,
              ),
            if (ticket != null)
              Text(
                ticket.routeLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: axis.textSecondary,
                ),
              ),
            if (_sale.checkout != null) ...[
              const SizedBox(height: AxisSpacing.xs),
              Text(
                'À payer : ${formatMoney(_sale.checkout!.total, _sale.checkout!.currency)}',
                style: theme.textTheme.titleSmall?.copyWith(color: axis.ink),
              ),
            ],
            if (sale.isHeld && sale.expiresAt != null) ...[
              const SizedBox(height: AxisSpacing.xs),
              SaleCountdown(expiresAt: sale.expiresAt!),
            ],
          ],
        ),
      ),
      const SizedBox(height: AxisSpacing.sm),
      if (_sale.refundDue)
        const _ErrorBanner(
          message:
              'Paiement reçu après l\'expiration : aucun billet n\'a été émis. Remboursement à traiter par Axis.',
        )
      else if (sale.status == 'EXPIRED')
        const _ErrorBanner(
          message:
              'Le délai est dépassé : la place n\'est plus tenue. Aucun billet n\'a été émis.',
        )
      else if (sale.status == 'CANCELLED')
        const _InfoBanner(message: 'Vente annulée. La place est libérée.')
      else
        const _InfoBanner(
          message:
              'Place tenue. Le billet sera émis dès que le serveur aura confirmé le paiement.',
        ),
      const SizedBox(height: AxisSpacing.md),
      if (over)
        AxisButton(
          label: 'Nouvelle vente',
          textColor: AxisButtonTextColor.ink,
          onPressed: _sale.busy ? null : _newSale,
        )
      else ...[
        if (_sale.checkout == null)
          AxisButton(
            label: _sale.busy ? 'Patientez…' : 'Réessayer le paiement',
            textColor: AxisButtonTextColor.ink,
            loading: _sale.busy,
            onPressed: _sale.busy ? null : _sell,
          )
        else ...[
          AxisButton(
            key: const Key('sale-verify'),
            label: _sale.busy ? 'Vérification…' : 'Vérifier le paiement',
            textColor: AxisButtonTextColor.ink,
            loading: _sale.busy,
            onPressed: _sale.busy ? null : _sale.verify,
          ),
          const SizedBox(height: AxisSpacing.xs),
          AxisButton(
            label: 'Rouvrir la page de paiement',
            variant: AxisButtonVariant.secondary,
            onPressed: _sale.busy ? null : _openPaymentPage,
          ),
        ],
        const SizedBox(height: AxisSpacing.xs),
        TextButton(
          onPressed: _sale.busy ? null : _cancel,
          child: Text(
            'Annuler la vente',
            style: theme.textTheme.labelMedium?.copyWith(color: axis.danger),
          ),
        ),
      ],
    ];
  }

  /// Écran Billet émis (`VenteOk.html`).
  Widget _buildIssuedView(BuildContext context, SaleTicket ticket) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onPrimary;
    final isMobileMoney = (_sale.quote?.online ?? false) ||
        (ticket.printInfo?.paymentMode.toLowerCase().contains('mobile') ??
            false);
    final formattedAmount = formatMoney(ticket.amount, ticket.currency);
    final subtitleText = isMobileMoney
        ? '$formattedAmount payés par Mobile Money'
        : '$formattedAmount encaissés en espèces';
    final phoneDisplay = _phone.text.trim();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // En-tête de confirmation sombre (`ink` + coche verte)
          Container(
            width: double.infinity,
            color: axis.ink,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.lg,
                  AxisSpacing.md,
                  AxisSpacing.lg,
                  AxisSpacing.lg,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: axis.success,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.check_rounded,
                        size: 32,
                        color: onDark,
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.sm),
                    Text(
                      'Billet émis',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: onDark,
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.xxs),
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: axis.borderStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Corps : carte récapitulative + remise du billet au passager
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AxisSpacing.md),
              children: [
                SaleIssuedCard(ticket: ticket),
                const SizedBox(height: AxisSpacing.lg),
                Text(
                  'REMETTRE LE BILLET AU PASSAGER',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: axis.textSecondary,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: AxisSpacing.xs),

                // 1. Partager le PDF / billet
                _DeliveryOptionTile(
                  key: const Key('sale-share'),
                  icon: Icons.share_outlined,
                  title: 'Partager le PDF',
                  subtitle: 'WhatsApp, Bluetooth, impression',
                  isPrimary: true,
                  onTap: () => _share(ticket),
                ),
                const SizedBox(height: AxisSpacing.xs),

                // 2. Envoyer le lien par SMS
                _DeliveryOptionTile(
                  icon: Icons.sms_outlined,
                  title: 'Envoyer le lien par SMS',
                  subtitle: phoneDisplay.isNotEmpty
                      ? 'Au $phoneDisplay'
                      : 'Au téléphone du passager',
                  onTap: () => _sendSms(ticket),
                ),
                const SizedBox(height: AxisSpacing.xs),

                // 3. Montrer le QR à l'écran
                _DeliveryOptionTile(
                  icon: Icons.qr_code_2_rounded,
                  title: 'Montrer le QR à l’écran',
                  subtitle: 'Le passager peut le photographier',
                  onTap: () => _showQrModal(ticket),
                ),
              ],
            ),
          ),

          // Pied de page : Accueil + Nouvelle vente (`VenteOk.html`)
          Container(
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.lg,
              AxisSpacing.sm,
              AxisSpacing.lg,
              AxisSpacing.md,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: axis.border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: AxisButton(
                      label: 'Accueil',
                      variant: AxisButtonVariant.secondary,
                      onPressed: () => context.go('/staff'),
                    ),
                  ),
                  const SizedBox(width: AxisSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: AxisButton(
                      label: 'Nouvelle vente',
                      textColor: AxisButtonTextColor.ink,
                      onPressed: _newSale,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte de confirmation d'un billet émis par le personnel (guichet ou contrôleur).
/// Affiche uniquement des données réelles du serveur ; montants en FCFA, aucune mention inventée.
class SaleIssuedCard extends StatelessWidget {
  const SaleIssuedCard({super.key, required this.ticket});

  final SaleTicket ticket;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final info = ticket.printInfo;
    final paid = (info != null && info.paid) || ticket.isIssued;

    return Container(
      padding: const EdgeInsets.all(AxisSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AxisRadius.lg),
        border: Border.all(color: axis.border),
        boxShadow: axis.floatingShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Billet émis · ${ticket.reference}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: axis.success,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AxisSpacing.sm,
                  vertical: AxisSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: axis.ink,
                  borderRadius: BorderRadius.circular(AxisRadius.md),
                ),
                child: Text(
                  'Siège ${ticket.seatNumber}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: axis.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AxisSpacing.sm),
          Divider(height: 1, color: axis.border),
          const SizedBox(height: AxisSpacing.sm),
          Text(
            'Passager : ${ticket.passengerName}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AxisSpacing.xxs),
          Text(
            'Siège : ${ticket.seatNumber}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AxisSpacing.xxs),
          Text(
            'Trajet : ${ticket.routeLabel}',
            style: theme.textTheme.bodyMedium,
          ),
          if (ticket.boardingDisplay.trim().isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'Embarquement : ${ticket.boardingDisplay.trim()}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
          if (ticket.alightingDisplay.trim().isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'Débarquement : ${ticket.alightingDisplay.trim()}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
          if (ticket.boardingAt != null) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              '${ticket.boardingDisplay.trim().isNotEmpty ? "Heure d'embarquement" : "Embarquement"} : ${formatFullDateTime(ticket.boardingAt!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
          if (ticket.departureAt != null) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'Départ : ${formatFullDateTime(ticket.departureAt!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AxisSpacing.xxs),
          Text(
            'Prix du billet : ${formatMoney(ticket.amount, ticket.currency)}',
            style: theme.textTheme.titleSmall,
          ),
          if (paid) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'Statut : Payé',
              style: theme.textTheme.labelMedium?.copyWith(color: axis.success),
            ),
          ],
          if (info != null && info.sale.trim().isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              info.sale.trim().startsWith('Vendeur')
                  ? info.sale.trim()
                  : 'Vendeur : ${info.sale.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
          if (info != null && info.paymentMode.trim().isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'Mode de paiement : ${info.paymentMode.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
          if (info != null && info.buyerIfu.trim().isNotEmpty) ...[
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'IFU de l\'acheteur : ${info.buyerIfu.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeliveryOptionTile extends StatelessWidget {
  const _DeliveryOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onPrimary;
    return Material(
      color: isPrimary ? axis.ink : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AxisRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AxisRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AxisSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AxisRadius.lg),
            border: Border.all(color: isPrimary ? axis.ink : axis.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPrimary ? axis.accent : axis.surfaceSoft,
                  borderRadius: BorderRadius.circular(AxisRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: AxisSizes.icon,
                  color: axis.ink,
                ),
              ),
              const SizedBox(width: AxisSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isPrimary ? onDark : axis.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isPrimary
                            ? axis.borderStrong
                            : axis.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isPrimary ? axis.accent : axis.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AxisSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AxisRadius.md),
        border: Border.all(color: axis.danger),
      ),
      child: Text(
        message,
        style: theme.textTheme.labelMedium?.copyWith(color: axis.danger),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AxisSpacing.sm),
      decoration: BoxDecoration(
        color: axis.accentSoft,
        borderRadius: BorderRadius.circular(AxisRadius.md),
        border: Border.all(color: axis.accent),
      ),
      child: Text(
        message,
        style: theme.textTheme.labelMedium?.copyWith(color: axis.onAccentSoft),
      ),
    );
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
    final axis = context.axis;
    final theme = Theme.of(context);
    final remaining = widget.expiresAt.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    return Text(
      seconds == 0
          ? 'Délai écoulé.'
          : 'Temps restant : ${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s',
      style: theme.textTheme.bodySmall?.copyWith(color: axis.textSecondary),
    );
  }
}
