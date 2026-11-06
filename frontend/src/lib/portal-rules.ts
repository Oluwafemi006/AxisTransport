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

// Libellé d'un départ dans la vente au guichet : parcours, date et heure, prix (ou son absence).
export function counterTripLabel(routeLabel: string, departure: string, price: string | null): string {
  return `${routeLabel} · ${departure} · ${price ?? "sans prix (non vendable)"}`;
}

// Texte d'erreur d'une action du portail, toujours en français et sans texte technique.
// `reason` : erreur levée par apiFetch (avec `status`) ou par le navigateur (sans `status`).
export const SEGMENT_FARE_MISSING_MESSAGE = "Tarif non disponible pour ce trajet. Choisissez un autre trajet ou contactez l'agence.";

// Refus du serveur pour un tronçon sans tarif : même message partout, jamais de texte technique.
export function isSegmentFareMissing(reason: unknown): boolean {
  const details = (reason as { details?: { code?: unknown } } | null | undefined)?.details;
  return details?.code === "segment_fare_missing";
}

export function actionErrorText(reason: unknown, failed: string): string {
  if (isSegmentFareMissing(reason)) return SEGMENT_FARE_MISSING_MESSAGE;
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

// Envoi d'un billet par WhatsApp : message et lien du billet préremplis. Numéro du passager seulement s'il est
// au format international ; sinon WhatsApp demande à l'agent de choisir le contact (aucun indicatif deviné).
export function soldTicketWhatsappHref(ticket: { reference: string; passenger_name: string; passenger_phone: string }, link: string): string {
  const text = `Bonjour ${ticket.passenger_name}, voici votre billet AXIS Transport ${ticket.reference} : ${link}`;
  const base = whatsappHref(ticket.passenger_phone) ?? "https://wa.me/";
  return `${base}?text=${encodeURIComponent(text)}`;
}

// ─── Dates à l'heure du Bénin ────────────────────────────────────────────────
// Le jour « aujourd'hui » est celui du Bénin (Africa/Porto-Novo, UTC+1), jamais celui du navigateur.
const BENIN_DAY = new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Porto-Novo", year: "numeric", month: "2-digit", day: "2-digit" });

// Date AAAA-MM-JJ, au Bénin, d'un instant (par défaut : maintenant).
export function beninDateKey(at: Date = new Date()): string {
  return BENIN_DAY.format(at);
}

// Date de départ de la recherche : obligatoire, au format AAAA-MM-JJ, pas avant aujourd'hui au Bénin.
export function searchDateError(value: string, today: string = beninDateKey()): string | null {
  if (!value) return "Choisissez une date de départ.";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) return "Date de départ invalide : choisissez-la dans le calendrier.";
  if (value < today) return "Choisissez une date à partir d’aujourd’hui.";
  return null;
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

// ─── Activation du compte du personnel ───────────────────────────────────────
// Validation du mot de passe choisi par l'invité.
export function activationPasswordError(password: string, confirm: string): string | null {
  if (!password) return "Saisissez un mot de passe.";
  if (password.length < 8) return "Le mot de passe doit comporter au moins 8 caractères.";
  if (password !== confirm) return "Les deux mots de passe ne correspondent pas.";
  return null;
}

// Redirection vers le portail adapté selon le rôle assigné.
export function staffPortalLoginUrl(role?: string | null): string {
  if (role === "COUNTER") return "/guichet";
  if (role === "CONTROLLER") return "/controleur";
  if (role === "ADMIN") return "/admin";
  return "/";
}

// ─── Disposition car Yutong (2 sièges - allée centrale - 2 sièges) ──────────
export interface SeatLayoutItem {
  id: number;
  number: string;
  row?: number | null;
  column?: number | null;
  status: string;
  status_display?: string;
}

export interface BusRow<T extends SeatLayoutItem> {
  rowNumber: number;
  left: T[];
  right: T[];
  aisleExtra?: T;
}

export function groupSeatsYutong<T extends SeatLayoutItem>(seats: T[]): BusRow<T>[] {
  const ordered = [...seats].sort((a, b) => {
    const rowA = a.row ?? 9999;
    const rowB = b.row ?? 9999;
    if (rowA !== rowB) return rowA - rowB;
    const colA = a.column ?? 9999;
    const colB = b.column ?? 9999;
    if (colA !== colB) return colA - colB;
    return a.number.localeCompare(b.number, undefined, { numeric: true });
  });

  if (ordered.some((s) => s.row !== null && s.row !== undefined)) {
    const map = new Map<number, T[]>();
    for (const seat of ordered) {
      const r = seat.row ?? 9999;
      if (!map.has(r)) map.set(r, []);
      map.get(r)!.push(seat);
    }
    return Array.from(map.entries()).map(([rowNumber, rowSeats]) => {
      if (rowSeats.length === 5) {
        return {
          rowNumber,
          left: rowSeats.slice(0, 2),
          aisleExtra: rowSeats[2],
          right: rowSeats.slice(3, 5),
        };
      }
      return {
        rowNumber,
        left: rowSeats.slice(0, 2),
        right: rowSeats.slice(2, 4),
      };
    });
  }

  const rows: BusRow<T>[] = [];
  for (let i = 0; i < ordered.length; i += 4) {
    const slice = ordered.slice(i, i + 4);
    rows.push({
      rowNumber: Math.floor(i / 4) + 1,
      left: slice.slice(0, 2),
      right: slice.slice(2, 4),
    });
  }
  return rows;
}



// Page suivante d'une liste paginée par le serveur : seul le numéro de `next` est repris, l'adresse reste la nôtre.
export function nextPagePath(path: string, next: string | null | undefined): string | null {
  const page = next ? new URL(next, "http://axis.invalid").searchParams.get("page") : null;
  if (!page) return null;
  const [base, query = ""] = path.split("?");
  const params = new URLSearchParams(query);
  params.set("page", page);
  return `${base}?${params.toString()}`;
}

// Tronçon de l'accueil (« Nos trajets ») : prix et prochain départ viennent du serveur (/client/segments/).
export interface SegmentOffer {
  origin_id: number;
  origin: string;
  destination_id: number;
  destination: string;
  price_fcfa: number;
  line_origin: string;
  next_departure: string | null;
  // Avec scope=all : faux pour une montée à un arrêt intermédiaire (vendue à bord, pas en ligne).
  online_boarding?: boolean;
}

export type SegmentDirection = "aller" | "retour";

// Même libellé que l'app : heure du Bénin, départ de la ville d'origine du bus.
export function segmentDepartureLabel(segment: Pick<SegmentOffer, "next_departure" | "line_origin">): string {
  if (!segment.next_departure) return "Aucun départ programmé";
  const at = new Date(segment.next_departure);
  const day = new Intl.DateTimeFormat("fr-FR", { timeZone: "Africa/Porto-Novo", weekday: "short", day: "numeric", month: "short" }).format(at);
  const hour = new Intl.DateTimeFormat("fr-FR", { timeZone: "Africa/Porto-Novo", hour: "2-digit", minute: "2-digit" }).format(at);
  return `Prochain départ : ${day}, départ de ${segment.line_origin} à ${hour}`;
}

// Recherche préremplie : date du prochain départ (jour du Bénin), sinon aujourd'hui.
export function segmentSearchDate(segment: Pick<SegmentOffer, "next_departure">, now: Date = new Date()): string {
  return segment.next_departure ? beninDateKey(new Date(segment.next_departure)) : beninDateKey(now);
}

// Demande de location : mêmes contrôles que l'application (benin_time.dart, rentalPeriodError) ; le serveur revérifie tout.
export function rentalPeriodError(startsAt: string, endsAt: string, now: Date = new Date()): string | null {
  if (!startsAt) return "Choisissez la date et l’heure de début.";
  if (!endsAt) return "Choisissez la date et l’heure de fin.";
  const start = new Date(startsAt).getTime();
  const end = new Date(endsAt).getTime();
  if (Number.isNaN(start)) return "Choisissez la date et l’heure de début.";
  if (Number.isNaN(end)) return "Choisissez la date et l’heure de fin.";
  if (start <= now.getTime()) return "Le début de la location doit être dans le futur.";
  if (end <= start) return "La fin de la location doit être après le début.";
  return null;
}

// Option chauffeur : imposée si le véhicule se loue uniquement avec chauffeur, impossible sans chauffeur disponible.
export function rentalWithDriver(vehicle: { driver_required?: boolean; driver_available?: boolean }, chosen: boolean): boolean {
  if (vehicle.driver_required) return true;
  if (!vehicle.driver_available) return false;
  return chosen;
}

// Corps envoyé à POST /client/rentals/ : le même que l'application (api_client.dart, createRental).
export function rentalRequestBody(vehicleId: number, startsAt: string, endsAt: string, withDriver: boolean) {
  return { vehicle: vehicleId, starts_at: new Date(startsAt).toISOString(), ends_at: new Date(endsAt).toISOString(), with_driver: withDriver };
}
