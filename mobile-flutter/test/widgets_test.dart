import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AxisTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('Phase 2 — Design System Widgets', () {
    testWidgets('AxisButton déclenche le callback et gère les états', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          AxisButton(
            label: 'Continuer',
            onPressed: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Continuer'), findsOneWidget);
      await tester.tap(find.byType(AxisButton));
      expect(tapped, isTrue);

      // État loading
      await tester.pumpWidget(
        _wrap(
          AxisButton(
            label: 'Chargement',
            loading: true,
            onPressed: () => tapped = false,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AxisCard rend son enfant correctement', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AxisCard(
            child: Text('Contenu carte'),
          ),
        ),
      );
      expect(find.text('Contenu carte'), findsOneWidget);
    });

    testWidgets('AxisHeader affiche le titre, sous-titre et bouton retour', (tester) async {
      var backTapped = false;
      await tester.pumpWidget(
        _wrap(
          AxisHeader(
            title: 'Mes réservations',
            subtitle: 'Historique des départs',
            onBack: () => backTapped = true,
          ),
        ),
      );

      expect(find.text('Mes réservations'), findsOneWidget);
      expect(find.text('Historique des départs'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      expect(backTapped, isTrue);
    });

    testWidgets('AxisTextField saisie et toggle mot de passe', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _wrap(
          AxisTextField(
            label: 'Mot de passe',
            controller: controller,
            isPassword: true,
          ),
        ),
      );

      expect(find.text('Mot de passe'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'secret123');
      expect(controller.text, 'secret123');

      // Bouton afficher/masquer le mot de passe
      final toggleBtn = find.byTooltip('Afficher le mot de passe');
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pump();
      expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
    });

    testWidgets('StatusChip affiche le label et l’icône', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusChip(
            label: 'Billet payé',
            variant: StatusChipVariant.success,
            icon: Icons.check,
          ),
        ),
      );
      expect(find.text('Billet payé'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('SegmentedToggle commute entre les options', (tester) async {
      var current = 'sans';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrap(
              SegmentedToggle<String>(
                options: const [
                  SegmentOption(value: 'sans', label: 'Sans chauffeur'),
                  SegmentOption(value: 'avec', label: 'Avec chauffeur'),
                ],
                selectedValue: current,
                onChanged: (val) => setState(() => current = val),
              ),
            );
          },
        ),
      );

      expect(find.text('Sans chauffeur'), findsOneWidget);
      expect(find.text('Avec chauffeur'), findsOneWidget);
      await tester.tap(find.text('Avec chauffeur'));
      expect(current, 'avec');
    });

    testWidgets('ChoiceCard affiche titre, prix et sélection', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrap(
              ChoiceCard(
                title: 'Formule confort',
                subtitle: 'Climatisation incluse',
                price: '15 000 F',
                unit: '/jour',
                selected: selected,
                onTap: () => setState(() => selected = !selected),
              ),
            );
          },
        ),
      );

      expect(find.text('Formule confort'), findsOneWidget);
      expect(find.text('Climatisation incluse'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('15 000 F'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byType(ChoiceCard));
      expect(selected, isTrue);
    });

    testWidgets('RouteStopsBar affiche les arrêts', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RouteStopsBar(
            stops: [
              RouteStopItem(name: 'Parakou', state: RouteStopState.passed),
              RouteStopItem(name: 'Savè', state: RouteStopState.current),
              RouteStopItem(name: 'Cotonou', state: RouteStopState.upcoming),
            ],
          ),
        ),
      );

      expect(find.text('Parakou'), findsOneWidget);
      expect(find.text('Savè'), findsOneWidget);
      expect(find.text('Cotonou'), findsOneWidget);
    });

    testWidgets('TimelineSteps affiche les étapes verticales', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TimelineSteps(
            steps: [
              TimelineStepItem(
                title: 'Déposé',
                meta: '08:00',
                state: TimelineStepState.done,
              ),
              TimelineStepItem(
                title: 'En route',
                state: TimelineStepState.now,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Déposé'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('En route'), findsOneWidget);
    });

    testWidgets('SeatMap sélectionne les sièges libres et ignore les occupés', (tester) async {
      String? selectedSeat;
      await tester.pumpWidget(
        _wrap(
          SeatMap(
            rows: const [
              SeatRowData([
                SeatCellData.seat(number: '1', status: SeatStatus.free),
                SeatCellData.seat(number: '2', status: SeatStatus.taken),
                SeatCellData.aisle(),
                SeatCellData.seat(number: '3', status: SeatStatus.free),
              ]),
            ],
            onSeatSelected: (s) => selectedSeat = s,
          ),
        ),
      );

      // Clic sur siège libre '1'
      await tester.tap(find.text('1'));
      expect(selectedSeat, '1');

      // Clic sur siège occupé '2' -> le callback n'est pas appelé
      selectedSeat = null;
      await tester.tap(find.text('2'));
      expect(selectedSeat, isNull);
    });

    testWidgets('PhotoSlots gère ajout et suppression', (tester) async {
      var added = false;
      var removedIndex = -1;

      await tester.pumpWidget(
        _wrap(
          PhotoSlots(
            photos: const [
              PhotoSlotItem(id: '1', label: 'Face avant'),
            ],
            onAdd: () => added = true,
            onRemove: (idx) => removedIndex = idx,
          ),
        ),
      );

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);

      await tester.tap(find.text('Photo'));
      expect(added, isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(removedIndex, 0);
    });

    testWidgets('QrScanFrame affiche l’instruction de scan', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const QrScanFrame(
            instruction: 'Placez le code QR au centre',
            animateLaser: false,
          ),
        ),
      );
      expect(find.text('Placez le code QR au centre'), findsOneWidget);
    });

    testWidgets('ScanResultSheet affiche les informations d’un billet valide', (tester) async {
      var actionCalled = false;
      await tester.pumpWidget(
        _wrap(
          ScanResultSheet(
            data: const ScanResultData(
              type: ScanResultType.valid,
              ticketNumber: 'AXS-123456',
              passengerName: 'Koffi Paul',
              seatNumber: '08',
              tripRoute: 'Parakou → Cotonou',
            ),
            onPrimaryAction: () => actionCalled = true,
          ),
        ),
      );

      expect(find.text('Billet valide'), findsOneWidget);
      expect(find.text('Koffi Paul'), findsOneWidget);
      expect(find.text('08'), findsOneWidget);

      await tester.tap(find.text('Valider l’embarquement'));
      expect(actionCalled, isTrue);
    });

    testWidgets('SkeletonBox effectue le rendu sans erreur', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              SkeletonBox(width: 100, height: 20),
              SkeletonBox.circle(size: 30),
            ],
          ),
        ),
      );
      expect(find.byType(SkeletonBox), findsNWidgets(2));
    });

    testWidgets('EmptyState affiche titre, description et bouton', (tester) async {
      var actionTriggered = false;
      await tester.pumpWidget(
        _wrap(
          EmptyState(
            title: 'Aucun colis',
            description: 'Vous n’avez aucun envoi en cours.',
            actionLabel: 'Créer un colis',
            onAction: () => actionTriggered = true,
          ),
        ),
      );

      expect(find.text('Aucun colis'), findsOneWidget);
      expect(find.text('Vous n’avez aucun envoi en cours.'), findsOneWidget);
      await tester.tap(find.text('Créer un colis'));
      expect(actionTriggered, isTrue);
    });

    testWidgets('AxisBottomNav bascule entre onglets', (tester) async {
      var index = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrap(
              AxisBottomNav(
                currentIndex: index,
                onTap: (i) => setState(() => index = i),
              ),
            );
          },
        ),
      );

      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Billets'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Colis'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);

      await tester.tap(find.text('Location'));
      expect(index, 2);
    });
  });
}
