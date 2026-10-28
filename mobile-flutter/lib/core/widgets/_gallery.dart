import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import 'widgets.dart';

/// Page galerie de vitrine des composants AXIS.
///
/// Exclusivement disponible en mode débogage (`kDebugMode`).
class AxisWidgetGalleryPage extends StatefulWidget {
  const AxisWidgetGalleryPage({super.key});

  @override
  State<AxisWidgetGalleryPage> createState() => _AxisWidgetGalleryPageState();
}

class _AxisWidgetGalleryPageState extends State<AxisWidgetGalleryPage> {
  int _toggleIndex = 0;
  String _choice = 'sans';
  String? _selectedSeat = '12';
  int _navIndex = 0;
  final List<PhotoSlotItem> _photos = [
    const PhotoSlotItem(id: '1', label: 'Face avant'),
    const PhotoSlotItem(id: '2', label: 'Emballage'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Galerie non disponible en production.')),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: AxisHeader(
              title: 'Galerie Composants',
              subtitle: 'Phase 2 — Design System Axis Mobile',
              variant: AxisHeaderVariant.client,
              onBack: () {},
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(AxisSpacing.md),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _sectionTitle('1. AxisButton'),
                AxisButton(
                  label: 'Bouton Principal',
                  onPressed: () {},
                  variant: AxisButtonVariant.primary,
                ),
                const SizedBox(height: AxisSpacing.xs),
                AxisButton(
                  label: 'Bouton Secondaire',
                  onPressed: () {},
                  variant: AxisButtonVariant.secondary,
                ),
                const SizedBox(height: AxisSpacing.xs),
                AxisButton(
                  label: 'Bouton Outline',
                  onPressed: () {},
                  variant: AxisButtonVariant.outline,
                ),
                const SizedBox(height: AxisSpacing.xs),
                AxisButton(
                  label: 'Bouton En chargement',
                  onPressed: () {},
                  loading: true,
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('2. AxisCard'),
                const AxisCard(
                  child: Text('Carte standard avec bordure 1px et rayon 18px'),
                ),
                const SizedBox(height: AxisSpacing.xs),
                const AxisCard(
                  floating: true,
                  child: Text('Carte flottante avec ombre douce Axis'),
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('3. AxisTextField'),
                const AxisTextField(
                  label: 'Nom complet',
                  hintText: 'Ex: KOUASSI Koffi',
                ),
                const SizedBox(height: AxisSpacing.xs),
                const AxisTextField(
                  label: 'Mot de passe',
                  isPassword: true,
                ),
                const SizedBox(height: AxisSpacing.xs),
                const AxisTextField(
                  label: 'Téléphone',
                  isPhone: true,
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('4. StatusChip'),
                const Wrap(
                  spacing: AxisSpacing.xs,
                  runSpacing: AxisSpacing.xs,
                  children: [
                    StatusChip(
                      label: 'Payé',
                      variant: StatusChipVariant.success,
                      icon: Icons.check_circle_outline,
                    ),
                    StatusChip(
                      label: 'En attente',
                      variant: StatusChipVariant.warning,
                      icon: Icons.access_time,
                    ),
                    StatusChip(
                      label: 'Annulé',
                      variant: StatusChipVariant.danger,
                      icon: Icons.error_outline,
                    ),
                    StatusChip(
                      label: 'Info trajet',
                      variant: StatusChipVariant.info,
                    ),
                    StatusChip(
                      label: 'Brouillon',
                      variant: StatusChipVariant.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('5. SegmentedToggle'),
                SegmentedToggle<int>(
                  options: const [
                    SegmentOption(value: 0, label: 'Sans chauffeur'),
                    SegmentOption(value: 1, label: 'Avec chauffeur'),
                  ],
                  selectedValue: _toggleIndex,
                  onChanged: (val) => setState(() => _toggleIndex = val),
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('6. ChoiceCard'),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceCard(
                        title: 'Sans chauffeur',
                        price: '45 000 F',
                        unit: '/jour',
                        selected: _choice == 'sans',
                        onTap: () => setState(() => _choice = 'sans'),
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.xs),
                    Expanded(
                      child: ChoiceCard(
                        title: 'Avec chauffeur',
                        price: '55 000 F',
                        unit: '/jour',
                        selected: _choice == 'avec',
                        onTap: () => setState(() => _choice = 'avec'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('7. RouteStopsBar'),
                const RouteStopsBar(
                  stops: [
                    RouteStopItem(name: 'Parakou', state: RouteStopState.passed),
                    RouteStopItem(name: 'Savè', state: RouteStopState.passed),
                    RouteStopItem(name: 'Kétou', state: RouteStopState.current),
                    RouteStopItem(name: 'Porto-Novo', state: RouteStopState.upcoming),
                    RouteStopItem(name: 'Cotonou', state: RouteStopState.upcoming),
                  ],
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('8. TimelineSteps'),
                const TimelineSteps(
                  steps: [
                    TimelineStepItem(
                      title: 'Déposé à l’agence',
                      meta: 'Parakou · 09:14',
                      state: TimelineStepState.done,
                    ),
                    TimelineStepItem(
                      title: 'En route vers Kétou',
                      meta: 'Étape en cours',
                      state: TimelineStepState.now,
                    ),
                    TimelineStepItem(
                      title: 'Arrivée à Cotonou',
                      meta: 'Prévue à 14:00',
                      state: TimelineStepState.todo,
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('9. SeatMap'),
                SeatMap(
                  rows: [
                    SeatRowData([
                      SeatCellData.seat(
                        number: '1',
                        status: _selectedSeat == '1'
                            ? SeatStatus.selected
                            : SeatStatus.free,
                      ),
                      const SeatCellData.seat(
                        number: '2',
                        status: SeatStatus.taken,
                      ),
                      const SeatCellData.aisle(),
                      SeatCellData.seat(
                        number: '3',
                        status: _selectedSeat == '3'
                            ? SeatStatus.selected
                            : SeatStatus.free,
                      ),
                      SeatCellData.seat(
                        number: '4',
                        status: _selectedSeat == '4'
                            ? SeatStatus.selected
                            : SeatStatus.free,
                      ),
                    ]),
                  ],
                  onSeatSelected: (seatNum) => setState(() {
                    _selectedSeat = _selectedSeat == seatNum ? null : seatNum;
                  }),
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('10. PhotoSlots'),
                PhotoSlots(
                  photos: _photos,
                  onAdd: () {
                    if (_photos.length < 3) {
                      setState(() {
                        _photos.add(
                          PhotoSlotItem(
                            id: '${_photos.length + 1}',
                            label: 'Photo ${_photos.length + 1}',
                          ),
                        );
                      });
                    }
                  },
                  onRemove: (idx) {
                    setState(() {
                      _photos.removeAt(idx);
                    });
                  },
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('11. QrScanFrame'),
                Container(
                  color: const Color(0xFF0E1B2C),
                  padding: const EdgeInsets.symmetric(vertical: AxisSpacing.lg),
                  child: const Center(
                    child: QrScanFrame(
                      animateLaser: false,
                    ),
                  ),
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('12. ScanResultSheet'),
                ScanResultSheet(
                  data: const ScanResultData(
                    type: ScanResultType.valid,
                    ticketNumber: 'AXS-984712',
                    passengerName: 'Bio Gounou',
                    seatNumber: '12',
                    tripRoute: 'Parakou → Cotonou',
                  ),
                  onPrimaryAction: () {},
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('13. SkeletonBox'),
                const Row(
                  children: [
                    SkeletonBox.circle(size: 44),
                    SizedBox(width: AxisSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 16),
                          SizedBox(height: AxisSpacing.xxs),
                          SkeletonBox(height: 12, width: 120),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('14. EmptyState'),
                EmptyState(
                  title: 'Aucun billet trouvé',
                  description: 'Vous n’avez encore aucun billet actif réservé.',
                  actionLabel: 'Réserver un départ',
                  onAction: () {},
                ),
                const SizedBox(height: AxisSpacing.lg),

                _sectionTitle('15. AxisBottomNav'),
                AxisBottomNav(
                  currentIndex: _navIndex,
                  onTap: (idx) => setState(() => _navIndex = idx),
                ),
                const SizedBox(height: AxisSpacing.xl),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AxisSpacing.sm),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

