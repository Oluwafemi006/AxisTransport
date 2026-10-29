/// Espacements, rayons et hauteurs de la spec (section 1, « Espacements, rayons, tailles »).
abstract final class AxisSpacing {
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;

  /// Alias de commodité pour la cohérence des widgets.
  static const double xxs = s4;
  static const double xs = s8;
  static const double sm = s12;
  static const double md = s16;
  static const double lg = s20;
  static const double xl = s24;

  /// Marge latérale des écrans.
  static const double screen = 16;

  /// Marge latérale des écrans de connexion et d'inscription (20–24 dans la spec).
  static const double screenAuth = 22;
}

abstract final class AxisRadius {
  /// Voyants de légende (plan de sièges).
  static const double legendDot = 5;

  /// Badge compact d'en-tête contrôleur.
  static const double badge = 6;

  /// Puces.
  static const double chip = 8;

  /// Cadre de porte dans le plan de sièges.
  static const double door = 10;

  /// Petits boutons, champs compacts.
  static const double small = 12;

  /// Boutons principaux et champs.
  static const double button = 14;
  static const double field = 14;

  /// Cartes.
  static const double card = 18;

  /// Feuilles du bas et en-têtes arrondis.
  static const double sheet = 22;

  /// Feuille modale de résultat de scan.
  static const double scanSheet = 26;

  /// En-tête arrondi de l'écran de connexion.
  static const double authHeader = 28;

  /// Avant arrondi de la silhouette du car (plan de sièges).
  static const double busFront = 40;

  /// Pastilles.
  static const double pill = 999;

  /// Alias de commodité pour la cohérence des widgets.
  static const double xs = chip;
  static const double sm = small;
  static const double md = button;
  static const double lg = card;
  static const double xl = sheet;
}

abstract final class AxisSizes {
  static const double primaryButton = 54;
  static const double secondaryButton = 48;
  static const double field = 50;

  /// Aucune cible tactile plus petite.
  static const double minTarget = 44;

  static const double seat = 46;
  static const double icon = 20;
  static const double navigationBar = 68;
}

