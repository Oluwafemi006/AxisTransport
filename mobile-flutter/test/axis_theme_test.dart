import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AxisTheme.light() : Material 3, couleur primaire et extension AxisTokens', () {
    final theme = AxisTheme.light();

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, const Color(0xFF0B3C74));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F6FA));

    final tokens = theme.extension<AxisTokens>();
    expect(tokens, isNotNull);
    expect(tokens!.accent, const Color(0xFFF5A524));
    expect(tokens.ink, const Color(0xFF0E1B2C));
  });

  testWidgets('context.axis lit les tokens du thème', (tester) async {
    late AxisTokens read;
    await tester.pumpWidget(
      MaterialApp(
        theme: AxisTheme.light(),
        home: Builder(
          builder: (context) {
            read = context.axis;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(read.accentSoft, const Color(0xFFFFF4DC));
  });
}

