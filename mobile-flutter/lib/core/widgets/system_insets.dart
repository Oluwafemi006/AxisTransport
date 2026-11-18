import 'package:flutter/widgets.dart';

/// Marges du système (barre d'état en haut, barre de navigation ou geste en bas) ajoutées à une marge
/// de mise en page. Depuis la cible Android 15 (targetSdk 35 et plus), l'application s'affiche bord à bord :
/// le contenu passe sous ces barres si on ne les ajoute pas. Sur un téléphone où elles valent 0, rien ne change.
/// Même principe que AxisHeader (MediaQuery.paddingOf(context).top).
EdgeInsets withSystemInsets(BuildContext context, EdgeInsets base, {bool top = false, bool bottom = false}) {
  final system = MediaQuery.paddingOf(context);
  return base.copyWith(
    top: base.top + (top ? system.top : 0),
    bottom: base.bottom + (bottom ? system.bottom : 0),
  );
}
