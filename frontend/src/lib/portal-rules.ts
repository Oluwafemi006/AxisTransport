// Règles d'affichage du site et du portail, sans dépendance : testées par `npm test` (tests/portal-rules.test.mjs).

export interface PlaceChoice {
  id: number;
  name: string;
}

// Liste d'une ville de recherche : toutes les villes sauf celle déjà choisie dans l'autre liste.
export function placeChoices<T extends PlaceChoice>(places: T[], excludedId: string): T[] {
  return excludedId ? places.filter((place) => String(place.id) !== excludedId) : places;
}

// Recherche de l'accueil : les deux villes sont obligatoires et différentes. null = recherche possible.
export function searchError(originId: string, destinationId: string): string | null {
  if (!originId || !destinationId) return "Choisissez une ville de départ et une destination.";
  if (originId === destinationId) return "La destination doit être différente de la ville de départ.";
  return null;
}

// Durée de blocage d'un siège (« ticket_hold_minutes ») : sans elle, aucune réservation n'est possible.
export function holdMinutesConfigured(settings: Array<{ key: string; value: unknown }>): boolean {
  const item = settings.find((setting) => setting.key === "ticket_hold_minutes");
  if (!item || item.value === null || item.value === "") return false;
  const minutes = Number(item.value);
  return Number.isInteger(minutes) && minutes > 0;
}

// Libellé d'un départ dans la vente au guichet : parcours, date et heure, prix TTC (ou son absence).
export function counterTripLabel(routeLabel: string, departure: string, price: string | null): string {
  return `${routeLabel} · ${departure} · ${price ?? "sans prix (non vendable)"}`;
}

// Texte d'erreur d'une action du portail, toujours en français et sans texte technique.
// `reason` : erreur levée par apiFetch (avec `status`) ou par le navigateur (sans `status`).
export function actionErrorText(reason: unknown, failed: string): string {
  const error = (reason ?? {}) as { status?: unknown; message?: unknown; name?: unknown };
  const status = typeof error.status === "number" ? error.status : null;
  if (status === null) {
    // Pas de réponse du serveur (réseau coupé, serveur arrêté) : le navigateur lève une TypeError.
    if (error.name === "TypeError") return `${failed} Le serveur ne répond pas : vérifiez la connexion et réessayez.`;
    return `${failed} Vérifiez les valeurs saisies et réessayez.`;
  }
  if (status === 401) return `${failed} Votre session a expiré : reconnectez-vous, puis recommencez.`;
  if (status === 403) return `${failed} Votre compte n’a pas le droit de faire cette action.`;
  if (status >= 500) return `${failed} Le serveur a rencontré un problème : réessayez dans quelques minutes.`;
  // Erreur métier (400, 404, 409…) : le serveur répond en français ; son message explique la cause.
  const message = typeof error.message === "string" ? error.message.trim() : "";
  if (!message || message === "Une erreur est survenue.") return `${failed} Vérifiez les valeurs saisies et réessayez.`;
  return `${failed} ${message}`;
}

// ─── Liens de contact du site public ─────────────────────────────────────────
// Jamais construits à partir du texte brut : seuls les chiffres (et un « + » initial) sont gardés,
// et un numéro invalide ne produit aucun lien (le texte reste affiché tel quel).
// 15 chiffres au plus : longueur maximale d'un numéro international (norme E.164).

// Lien d'appel : chiffres et « + » du texte saisi ; null si le numéro est vide ou invalide.
export function phoneHref(text: string | null | undefined): string | null {
  const kept = (text ?? "").replace(/[^\d+]/g, "");
  return /^\+?\d{1,15}$/.test(kept) ? `tel:${kept}` : null;
}

// Lien WhatsApp (wa.me) : numéro au format international (« + » ou « 00 » suivi de l'indicatif),
// écrit sans « + » ni espaces dans le lien ; null s'il est vide ou pas au format international.
export function whatsappHref(text: string | null | undefined): string | null {
  const compact = (text ?? "").replace(/[\s.\-()]/g, "");
  const match = /^(?:\+|00)(\d{1,15})$/.exec(compact);
  return match ? `https://wa.me/${match[1]}` : null;
}

// ─── Vente au guichet ────────────────────────────────────────────────────────
// Départs proposés au guichet : planifiés ou en embarquement, itinéraire actif, pas encore partis,
// du plus proche au plus lointain.
export interface SellableTrip {
  status: string;
  departure_at: string;
  route_detail: { active: boolean };
}

export function upcomingSellableTrips<T extends SellableTrip>(trips: T[], now: Date = new Date()): T[] {
  return trips
    .filter((trip) => trip.route_detail.active && ["SCHEDULED", "BOARDING"].includes(trip.status) && Date.parse(trip.departure_at) > now.getTime())
    .sort((a, b) => Date.parse(a.departure_at) - Date.parse(b.departure_at));
}
