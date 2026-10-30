import 'package:flutter/material.dart';

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
  });

  final String? tripSubtitle;
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
  int _paymentIndex = 0; // 0 = Espèces, 1 = Mobile Money
  String? _formError;
  bool _sending = false;

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
        _formError =
            'Veuillez renseigner l’expéditeur, le destinataire et la description du colis.';
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

    _send();
  }

  Future<void> _send() async {
    final api = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final options = await api.saleOptions();
      final trips = options['trips'] as List? ?? const [];
      final stops = trips.isEmpty
          ? const <RouteStopInfo>[]
          : SaleTrip.fromJson(Map<String, dynamic>.from(trips.first as Map)).stops;
      if (stops.isEmpty) {
        setState(() => _formError = 'Aucun départ en cours pour ce colis.');
        return;
      }
      final result = await api.createParcel({
        'sender_name': _senderName.text.trim(),
        'sender_phone': _senderPhone.text.trim(),
        'recipient_name': _recipientName.text.trim(),
        'recipient_phone': _recipientPhone.text.trim(),
        'origin': stops.first.id,
        'destination': _selectedDestinationId,
        'description': _description.text.trim(),
      }, [for (final photo in _photos) ?photo.imageBytes]);
      ref.read(staffActivityProvider.notifier).changed();
      messenger.showSnackBar(
        SnackBar(content: Text('Colis ${result['tracking_number']} enregistré.')),
      );
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final hasPhoto = _photos.isNotEmpty;
    final fare = widget.fareFcfa;
    final isMobileMoney = _paymentIndex == 1;

    final String submitLabel;
    if (fare != null) {
      final formattedFare = formatMoney(fare, 'FCFA');
      submitLabel = isMobileMoney
          ? 'Demander le paiement de $formattedFare & enregistrer'
          : 'Encaisser $formattedFare & enregistrer';
    } else {
      submitLabel = isMobileMoney
          ? 'Demander le paiement & enregistrer'
          : 'Encaisser & enregistrer';
    }

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
                      Text(
                        'ARRÊT DE DESTINATION *',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: axis.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AxisSpacing.xs),
                      if (_locations.isNotEmpty)
                        DropdownButtonFormField<int>(
                          initialValue: _selectedDestinationId,
                          isExpanded: true,
                          items: _locations
                              .map(
                                (loc) => DropdownMenuItem<int>(
                                  value: loc.id,
                                  child: Text(loc.name),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _selectedDestinationId = val),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AxisSpacing.md,
                            vertical: AxisSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: axis.surfaceSoft,
                            borderRadius: BorderRadius.circular(AxisRadius.md),
                            border: Border.all(color: axis.border),
                          ),
                          child: Text(
                            'Aucun arrêt chargé depuis l’API',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: axis.textSecondary,
                            ),
                          ),
                        ),
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
                          Text(
                            'TARIF COLIS (FCFA)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: axis.textSecondary,
                            ),
                          ),
                          Text(
                            fare != null
                                ? formatMoney(fare, 'FCFA')
                                : 'Tarif selon grille agence',
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
                onPressed: hasPhoto ? _handleSubmit : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

