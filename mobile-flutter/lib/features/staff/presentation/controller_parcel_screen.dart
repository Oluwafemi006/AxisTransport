import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../../sales/sale_models.dart';
import 'parcel_camera_screen.dart';
import 'staff_home_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_spacing.dart';
import '../../../core/theme/axis_tokens.dart';
import '../../../core/widgets/axis_button.dart';
import '../../../core/widgets/axis_header.dart';
import '../../../core/widgets/axis_text_field.dart';
import '../../../core/widgets/photo_slots.dart';
import '../../../core/widgets/segmented_toggle.dart';
import '../../../shared/payment_link.dart';

/// Exécutée hors de l'écran : réduit chaque photo pour rester léger en 3G.
List<List<int>> compressParcelPhotos(List<List<int>> photos) {
  const settings = ParcelPhotoCaptureSettings();
  return [
    for (final bytes in photos)
      () {
        final decoded = img.decodeImage(Uint8List.fromList(bytes));
        if (decoded == null) return bytes;
        final resized = decoded.width > decoded.height
            ? (decoded.width > settings.maxWidthPx
                  ? img.copyResize(decoded, width: settings.maxWidthPx)
                  : decoded)
            : (decoded.height > settings.maxWidthPx
                  ? img.copyResize(decoded, height: settings.maxWidthPx)
                  : decoded);
        return img.encodeJpg(resized, quality: settings.jpegQuality).toList();
      }(),
  ];
}

/// Paramètres de compression d'image avant envoi (largeur max ~1280 px, qualité JPEG ~70).
class ParcelPhotoCaptureSettings {
  const ParcelPhotoCaptureSettings({
    this.maxWidthPx = 1280,
    this.jpegQuality = 70,
  });

  final int maxWidthPx;
  final int jpegQuality;
}

/// Écran contrôleur « Enregistrer un colis » (`CtrlColis.html`).
///
/// L'API `/api/v1/staff/` n'exposant pas encore la création de colis avec
/// envoi multipart de 1 à 3 photos, cet écran fonctionne en UI pure prête à
/// brancher (documenté dans `docs/design/MISSING_FEATURES.md`).
class ControllerParcelScreen extends ConsumerStatefulWidget {
  const ControllerParcelScreen({
    super.key,
    this.tripSubtitle,
    this.initialPhotos = const <PhotoSlotItem>[],
    this.destinations,
    this.fareFcfa,
    this.onCapturePhoto,
    this.onSubmit,
    this.openPayment,
  });

  final String? tripSubtitle;

  /// Ouverture de la page Mobile Money ; remplaçable dans les tests (aucun navigateur).
  final Future<bool> Function(Uri url)? openPayment;
  final List<PhotoSlotItem> initialPhotos;
  final List<Place>? destinations;
  final num? fareFcfa;
  final Future<PhotoSlotItem?> Function(ParcelPhotoCaptureSettings settings)?
  onCapturePhoto;
  final ValueChanged<Map<String, dynamic>>? onSubmit;

  @override
  ConsumerState<ControllerParcelScreen> createState() =>
      _ControllerParcelScreenState();
}

class _ControllerParcelScreenState
    extends ConsumerState<ControllerParcelScreen> {
  static const _compressionSettings = ParcelPhotoCaptureSettings();

  late final List<PhotoSlotItem> _photos = List<PhotoSlotItem>.from(
    widget.initialPhotos,
  );

  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();

  List<Place> _locations = const [];
  int? _selectedDestinationId;
  // Départs de l'agent (renvoyés par le serveur) : départ et destination se choisissent sur le trajet du bus.
  List<SaleTrip> _trips = const [];
  int? _tripId;
  int? _originId;
  int _paymentIndex = 0; // 0 = Espèces, 1 = Mobile Money
  String? _formError;
  bool _sending = false;
  num? _serverFare;
  String? _savedTrackingNumber;
  // Encaissement après l'enregistrement : identifiant et prix renvoyés par le serveur.
  int? _savedParcelId;
  num? _savedAmount;
  bool _parcelPaid = false;
  bool _paying = false;
  String? _checkoutUrl;
  String? _paymentError;

  @override
  void initState() {
    super.initState();
    if (widget.destinations != null) {
      _locations = widget.destinations!;
      if (_locations.isNotEmpty) {
        _selectedDestinationId = _locations.first.id;
      }
    } else {
      _loadLocations();
    }
    if (widget.fareFcfa == null) _loadFare();
  }

  Future<void> _loadFare() async {
    try {
      final options = await ref.read(apiClientProvider).saleOptions();
      final trips = <SaleTrip>[
        for (final raw in (options['trips'] as List? ?? const []))
          if (raw is Map) SaleTrip.fromJson(Map<String, dynamic>.from(raw)),
      ].where((trip) => trip.stops.length >= 2).toList();
      if (!mounted) return;
      setState(() {
        _serverFare = options['parcel_base_fcfa'] as num?;
        _trips = trips;
        if (trips.isNotEmpty) _chooseTrip(trips.first.id);
      });
    } catch (_) {
      // Sans réponse, aucun prix ni départ n'est affiché : rien n'est estimé ici.
    }
  }

  SaleTrip? get _trip {
    for (final trip in _trips) {
      if (trip.id == _tripId) return trip;
    }
    return null;
  }

  /// Arrêt actuel par défaut : la dernière arrivée confirmée, sinon le premier arrêt du trajet.
  void _chooseTrip(int id) {
    _tripId = id;
    final trip = _trip;
    if (trip == null) return;
    var origin = trip.stops.first;
    for (final stop in trip.stops.take(trip.stops.length - 1)) {
      if (trip.arrivedStopIds.contains(stop.id)) origin = stop;
    }
    _chooseOrigin(origin.id);
  }

  void _chooseOrigin(int id) {
    _originId = id;
    final after = _stopsAfter(id);
    if (!after.any((stop) => stop.id == _selectedDestinationId)) {
      _selectedDestinationId = after.isEmpty ? null : after.last.id;
    }
  }

  List<RouteStopInfo> _stopsAfter(int? originId) {
    final stops = _trip?.stops ?? const <RouteStopInfo>[];
    final index = stops.indexWhere((stop) => stop.id == originId);
    return index < 0 ? const [] : stops.sublist(index + 1);
  }

  String _nameOf(int? id) {
    for (final stop in _trip?.stops ?? const <RouteStopInfo>[]) {
      if (stop.id == id) return stop.name;
    }
    for (final place in _locations) {
      if (place.id == id) return place.name;
    }
    return '';
  }

  @override
  void dispose() {
    _senderName.dispose();
    _senderPhone.dispose();
    _recipientName.dispose();
    _recipientPhone.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    try {
      final list = await ref.read(apiClientProvider).locations();
      if (!mounted) return;
      setState(() {
        _locations = list;
        if (_selectedDestinationId == null && list.isNotEmpty) {
          _selectedDestinationId = list.first.id;
        }
      });
    } catch (_) {}
  }

  Future<void> _handleAddPhoto() async {
    if (_photos.length >= 3) return;
    PhotoSlotItem? captured;
    if (widget.onCapturePhoto != null) {
      captured = await widget.onCapturePhoto!(_compressionSettings);
    } else {
      captured = await _showCameraCaptureSheet(_photos.length + 1);
    }
    if (!mounted || captured == null) return;
    setState(() {
      _photos.add(captured!);
      _formError = null;
    });
  }

  /// Caméra intégrée à l'application : la photo revient directement dans sa case.
  Future<PhotoSlotItem?> _showCameraCaptureSheet(int index) async {
    final bytes = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => const ParcelCameraScreen()),
    );
    if (bytes == null) return null;
    return PhotoSlotItem(
      id: 'photo-$index',
      label: 'Photo $index',
      imageBytes: bytes,
    );
  }

  void _handleRemovePhoto(int index) {
    if (index < 0 || index >= _photos.length) return;
    setState(() {
      _photos.removeAt(index);
    });
  }

  void _handleSubmit() {
    if (_photos.isEmpty || _sending) return;
    if (_senderName.text.trim().isEmpty ||
        _senderPhone.text.trim().isEmpty ||
        _recipientName.text.trim().isEmpty ||
        _recipientPhone.text.trim().isEmpty ||
        _description.text.trim().isEmpty) {
      setState(() {
        _formError = 'Veuillez renseigner l’expéditeur, le destinataire et la description du colis.';
      });
      return;
    }

    setState(() => _formError = null);

    final payload = <String, dynamic>{
      'photos_count': _photos.length,
      'max_width_px': _compressionSettings.maxWidthPx,
      'jpeg_quality': _compressionSettings.jpegQuality,
      'sender_name': _senderName.text.trim(),
      'sender_phone': _senderPhone.text.trim(),
      'recipient_name': _recipientName.text.trim(),
      'recipient_phone': _recipientPhone.text.trim(),
      'destination_id': _selectedDestinationId,
      'description': _description.text.trim(),
      'payment_mode': _paymentIndex == 0 ? 'Espèces' : 'Mobile Money',
      'fare_fcfa': widget.fareFcfa,
    };

    if (widget.onSubmit != null) {
      widget.onSubmit!(payload);
      return;
    }

    _confirmAndSend();
  }

  /// Récapitulatif avant l'envoi : départ, destination et départ du bus.
  Future<void> _confirmAndSend() async {
    final trip = _trip;
    if (trip == null || _originId == null || _selectedDestinationId == null) {
      setState(
        () => _formError = 'Choisissez le départ du bus, le départ et la destination du colis.',
      );
      return;
    }
    final when = trip.departureAt == null
        ? ''
        : ', départ du ${formatFullDateTime(trip.departureAt!.toLocal())}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le colis'),
        content: Text(
          'Colis ${_nameOf(_originId)} → ${_nameOf(_selectedDestinationId)}$when (bus ${trip.label}).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Corriger'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (ok == true) await _send();
  }

  Future<void> _send() async {
    final api = ref.read(apiClientProvider);
    setState(() => _sending = true);
    try {
      final trip = _trip;
      if (trip == null || _originId == null) {
        setState(() => _formError = 'Aucun départ en cours pour ce colis.');
        return;
      }
      final result = await api.createParcel(
        {
          'sender_name': _senderName.text.trim(),
          'sender_phone': _senderPhone.text.trim(),
          'recipient_name': _recipientName.text.trim(),
          'recipient_phone': _recipientPhone.text.trim(),
          'trip': trip.id,
          'origin': _originId,
          'destination': _selectedDestinationId,
          'description': _description.text.trim(),
        },
        await compute(compressParcelPhotos, [
          for (final photo in _photos) ?photo.imageBytes,
        ]),
      );
      ref.read(staffActivityProvider.notifier).changed();
      if (mounted) {
        setState(() {
          _savedTrackingNumber = '${result['tracking_number']}';
          _savedParcelId = (result['id'] as num?)?.toInt();
          _savedAmount = result['amount'] as num?;
          _parcelPaid = false;
          _checkoutUrl = null;
          _paymentError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Moyen de paiement actif choisi dans le formulaire : espèces (hors ligne) ou Mobile Money (en ligne).
  Future<PaymentMethod?> _chosenMethod() async {
    final methods = await ref.read(apiClientProvider).paymentMethods();
    final wantOnline = _paymentIndex == 1;
    return methods.where((m) => m.active && m.online == wantOnline).firstOrNull;
  }

  Future<void> _collect() async {
    final id = _savedParcelId;
    if (id == null || _paying) return;
    final amount = _savedAmount;
    setState(() {
      _paying = true;
      _paymentError = null;
    });
    PaymentMethod? method;
    try {
      method = await _chosenMethod();
    } on ApiException catch (e) {
      if (mounted) setState(() => _paymentError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _paymentError = 'Les moyens de paiement n’ont pas pu être chargés. Vérifiez la connexion et réessayez.',
        );
      }
    }
    if (mounted) setState(() => _paying = false);
    if (!mounted || _paymentError != null) return;
    if (method == null) {
      setState(
        () => _paymentError = _paymentIndex == 1
            ? 'Le paiement Mobile Money n’est pas activé. Prévenez l’administrateur, ou encaissez en espèces.'
            : 'Le paiement en espèces n’est pas activé. Prévenez l’administrateur.',
      );
      return;
    }
    // Espèces : l'agent confirme avoir reçu le montant, avant tout appel au serveur.
    if (!method.online) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Espèces reçues ?'),
          content: Text(
            'Confirmez avoir reçu ${amount ?? ''} FCFA de l’expéditeur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Non'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Oui, reçues'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _paying = true);
    try {
      final result = await ref.read(apiClientProvider).payParcel(id, method.id);
      final checkout = result['checkout'];
      if (checkout is Map && checkout['payment_url'] is String) {
        final url = checkout['payment_url'] as String;
        if (mounted) setState(() => _checkoutUrl = url);
        var opened = false;
        try {
          opened = await (widget.openPayment ?? openPaymentPage)(
            Uri.parse(url),
          );
        } catch (_) {}
        if (!opened && mounted) {
          setState(
            () => _paymentError = 'La page de paiement n’a pas pu s’ouvrir. Réessayez avec « Ouvrir la page de paiement ».',
          );
        }
      } else {
        if (mounted) setState(() => _parcelPaid = true);
        ref.read(staffActivityProvider.notifier).changed();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _paymentError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _paymentError = 'L’encaissement n’a pas abouti. Vérifiez la connexion et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _verifyPayment() async {
    final id = _savedParcelId;
    if (id == null || _paying) return;
    setState(() {
      _paying = true;
      _paymentError = null;
    });
    try {
      await ref.read(apiClientProvider).verifyParcelPayment(id);
      if (mounted) setState(() => _parcelPaid = true);
      ref.read(staffActivityProvider.notifier).changed();
    } on ApiException catch (e) {
      if (mounted) setState(() => _paymentError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _paymentError = 'La vérification n’a pas abouti. Vérifiez la connexion et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Widget _paymentBlock(ThemeData theme, AxisTokens axis) {
    if (_savedParcelId == null) return const SizedBox.shrink();
    final children = <Widget>[];
    if (_parcelPaid) {
      children.add(
        Text(
          'Colis payé.',
          key: const Key('parcel-paid'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: axis.success),
        ),
      );
    } else if (_savedAmount == null) {
      children.add(
        Text(
          'Prix du colis pas encore fixé : l’agence l’encaissera.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: axis.textSecondary,
          ),
        ),
      );
    } else {
      children.add(
        AxisButton(
          key: const Key('parcel-pay'),
          label: _paymentIndex == 1
              ? 'Demander $_savedAmount FCFA par Mobile Money'
              : 'Encaisser $_savedAmount FCFA en espèces',
          loading: _paying,
          onPressed: _paying ? null : _collect,
        ),
      );
      if (_checkoutUrl != null) {
        children.addAll([
          const SizedBox(height: AxisSpacing.xs),
          AxisButton(
            label: 'Ouvrir la page de paiement',
            variant: AxisButtonVariant.outline,
            onPressed: _paying
                ? null
                : () => (widget.openPayment ?? openPaymentPage)(
                    Uri.parse(_checkoutUrl!),
                  ),
          ),
          const SizedBox(height: AxisSpacing.xs),
          AxisButton(
            key: const Key('parcel-verify'),
            label: 'Vérifier le paiement',
            variant: AxisButtonVariant.outline,
            onPressed: _paying ? null : _verifyPayment,
          ),
        ]);
      }
    }
    if (_paymentError != null) {
      children.addAll([
        const SizedBox(height: AxisSpacing.xs),
        Text(
          _paymentError!,
          key: const Key('parcel-pay-error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: axis.danger),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        const SizedBox(height: AxisSpacing.lg),
      ],
    );
  }

  void _newParcel() {
    setState(() {
      _savedTrackingNumber = null;
      _savedParcelId = null;
      _savedAmount = null;
      _parcelPaid = false;
      _checkoutUrl = null;
      _paymentError = null;
      _photos.clear();
      for (final field in [
        _senderName,
        _senderPhone,
        _recipientName,
        _recipientPhone,
        _description,
      ]) {
        field.clear();
      }
    });
  }

  Widget _buildConfirmation(String code) {
    final theme = Theme.of(context);
    final axis = context.axis;
    return Scaffold(
      body: Column(
        children: [
          AxisHeader(
            title: 'Colis enregistré',
            variant: AxisHeaderVariant.controller,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AxisSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Numéro de suivi',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: axis.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SelectableText(
                        code,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: axis.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.lg),
                    _paymentBlock(theme, axis),
                    AxisButton(
                      key: const Key('parcel-share'),
                      label: 'Partager le numéro',
                      textColor: AxisButtonTextColor.ink,
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text:
                              'AXIS Transport : suivez votre colis avec le numéro $code',
                        ),
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.sm),
                    AxisButton(
                      key: const Key('parcel-new'),
                      label: 'Nouveau colis',
                      variant: AxisButtonVariant.secondary,
                      onPressed: _newParcel,
                    ),
                  ],
                ),
              ),
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
    final hasPhoto = _photos.isNotEmpty;
    final fare = widget.fareFcfa ?? _serverFare;
    final submitLabel = _sending ? 'Envoi en cours…' : 'Enregistrer le colis';
    final savedCode = _savedTrackingNumber;
    if (savedCode != null) return _buildConfirmation(savedCode);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AxisHeader(
            variant: AxisHeaderVariant.controller,
            title: 'Nouveau colis',
            subtitle: widget.tripSubtitle ?? 'Enregistrement au départ',
            onBack: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/staff');
              }
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AxisSpacing.md),
              children: [
                if (_formError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AxisSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AxisRadius.md),
                      border: Border.all(color: axis.danger),
                    ),
                    child: Text(
                      _formError!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: axis.danger,
                      ),
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.md),
                ],

                // 1. Photos obligatoires (1 à 3)
                PhotoSlots(
                  photos: _photos,
                  maxPhotos: 3,
                  onAdd: _handleAddPhoto,
                  onRemove: _handleRemovePhoto,
                ),
                if (!hasPhoto) ...[
                  const SizedBox(height: AxisSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AxisSpacing.sm,
                      vertical: AxisSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: axis.accentSoft,
                      borderRadius: BorderRadius.circular(AxisRadius.md),
                      border: Border.all(color: axis.warning),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: axis.warningText,
                        ),
                        const SizedBox(width: AxisSpacing.xs),
                        Expanded(
                          child: Text(
                            'Ajoutez au moins une photo pour enregistrer.',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: axis.warningText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AxisSpacing.md),

                // 2. Expéditeur
                Text(
                  'EXPÉDITEUR',
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AxisTextField(
                          label: 'Nom complet *',
                          hintText: 'Nom expéditeur',
                          controller: _senderName,
                        ),
                      ),
                      const SizedBox(width: AxisSpacing.sm),
                      Expanded(
                        child: AxisTextField(
                          label: 'Téléphone *',
                          hintText: '+229 01 ·· ·· ··',
                          controller: _senderPhone,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AxisSpacing.md),

                // 3. Destinataire
                Text(
                  'DESTINATAIRE',
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AxisTextField(
                          label: 'Nom complet *',
                          hintText: 'Nom destinataire',
                          controller: _recipientName,
                        ),
                      ),
                      const SizedBox(width: AxisSpacing.sm),
                      Expanded(
                        child: AxisTextField(
                          label: 'Téléphone *',
                          hintText: '+229 01 ·· ·· ··',
                          controller: _recipientPhone,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AxisSpacing.md),

                // 4. Destination & contenu
                Text(
                  'DESTINATION & CONTENU',
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_trips.isEmpty)
                        Text(
                          'Aucun départ disponible : le colis ne peut pas être enregistré.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: axis.textSecondary,
                          ),
                        )
                      else ...[
                        Text(
                          'BUS *',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: axis.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.xs),
                        DropdownButtonFormField<int>(
                          key: ValueKey('trip-$_tripId'),
                          initialValue: _tripId,
                          isExpanded: true,
                          items: [
                            for (final trip in _trips)
                              DropdownMenuItem<int>(
                                value: trip.id,
                                child: Text(
                                  trip.departureAt == null
                                      ? trip.label
                                      : '${trip.label} · ${formatDateTime(trip.departureAt!.toLocal())}',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _chooseTrip(val));
                          },
                        ),
                        const SizedBox(height: AxisSpacing.sm),
                        Text(
                          'DÉPART DU COLIS *',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: axis.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.xs),
                        DropdownButtonFormField<int>(
                          key: ValueKey('origin-$_tripId-$_originId'),
                          initialValue: _originId,
                          isExpanded: true,
                          items: [
                            for (final stop
                                in (_trip?.stops ?? const <RouteStopInfo>[])
                                    .take(
                                      ((_trip?.stops.length ?? 1) - 1).clamp(
                                        0,
                                        99,
                                      ),
                                    ))
                              DropdownMenuItem<int>(
                                value: stop.id,
                                child: Text(stop.name),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _chooseOrigin(val));
                          },
                        ),
                        const SizedBox(height: AxisSpacing.sm),
                        Text(
                          'DESTINATION DU COLIS *',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: axis.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.xs),
                        DropdownButtonFormField<int>(
                          key: ValueKey('destination-$_tripId-$_originId'),
                          initialValue: _selectedDestinationId,
                          isExpanded: true,
                          items: [
                            for (final stop in _stopsAfter(_originId))
                              DropdownMenuItem<int>(
                                value: stop.id,
                                child: Text(stop.name),
                              ),
                          ],
                          onChanged: (val) =>
                              setState(() => _selectedDestinationId = val),
                        ),
                      ],
                      const SizedBox(height: AxisSpacing.sm),
                      AxisTextField(
                        label: 'Description & poids estimé *',
                        hintText: 'Ex. Carton vêtements ~8 kg',
                        controller: _description,
                      ),
                      const SizedBox(height: AxisSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'TARIF COLIS (FCFA)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: axis.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            fare != null
                                ? formatMoney(fare, 'FCFA')
                                : 'À fixer par l’agence',
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AxisSpacing.md),

                // 5. Paiement (Espèces / Mobile Money)
                Text(
                  'PAIEMENT',
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
                  selectedValue: _paymentIndex,
                  onChanged: (idx) => setState(() => _paymentIndex = idx),
                ),
              ],
            ),
          ),

          // Pied de page : bouton désactivé sans photo
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
              child: AxisButton(
                key: const Key('parcel-submit'),
                label: submitLabel,
                textColor: AxisButtonTextColor.ink,
                onPressed: hasPhoto && !_sending ? _handleSubmit : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
