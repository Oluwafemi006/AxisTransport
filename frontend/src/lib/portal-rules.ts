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

// Moyen de paiement encaissé au guichet (espèces…) : actif et non « en ligne ». Sans lui, le guichet ne peut pas encaisser.
export function offlinePaymentConfigured(methods: Array<{ code: string; active: boolean; online?: boolean }>): boolean {
  return methods.some((method) => method.active && method.online !== true && !["FEDAPAY", "KKIAPAY"].includes(method.code.toUpperCase()));
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

// Envoi d'un billet par WhatsApp : message et lien du billet préremplis. Numéro calculé par le serveur
// (`whatsapp_number`, phone.py) ; à défaut, numéro du passager déjà au format international ; sinon, repli :
// WhatsApp demande à l'agent de choisir le contact (aucun indicatif deviné ici).
export function soldTicketWhatsappHref(ticket: { reference: string; passenger_name: string; passenger_phone: string; whatsapp_number?: string | null }, link: string): string {
  const text = `Bonjour ${ticket.passenger_name}, voici votre billet AXIS Transport ${ticket.reference} : ${link}`;
  const server = /^\d{8,15}$/.test(ticket.whatsapp_number ?? "") ? `https://wa.me/${ticket.whatsapp_number}` : null;
  const base = server ?? whatsappHref(ticket.passenger_phone) ?? "https://wa.me/";
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

// Clé d'une écriture (méthode, adresse, contenu) ; null pour une lecture ou un envoi de fichier.
export function writeKey(method: string | undefined, path: string, body: unknown): string | null {
  const verb = (method || "GET").toUpperCase();
  if (verb === "GET" || verb === "HEAD" || (body !== undefined && body !== null && typeof body !== "string")) return null;
  return `${verb} ${path} ${body ?? ""}`;
}

// Double clic : une écriture identique déjà en cours n'est pas renvoyée au serveur ; le second appel reçoit la même réponse.
export function shareInFlight<T>(pending: Map<string, Promise<unknown>>, key: string | null, start: () => Promise<T>): Promise<T> {
  if (key === null) return start();
  const current = pending.get(key);
  if (current) return current as Promise<T>;
  const request = start().finally(() => pending.delete(key));
  pending.set(key, request);
  return request;
}

// Bilan global : période AAAA-MM-JJ valide, pas de fin avant le début, pas de date future.
export function reportPeriodError(start: string, end: string, today: string = beninDateKey()): string | null {
  const valid = /^\d{4}-\d{2}-\d{2}$/;
  if (!valid.test(start) || !valid.test(end)) return "Indiquez une date de début et une date de fin.";
  if (end < start) return "La date de fin doit être postérieure ou égale à la date de début.";
  if (end > today) return "La date de fin ne peut pas dépasser aujourd'hui.";
  return null;
}

// ─── Location de véhicules (mêmes règles et messages que mobile-flutter/lib/features/rentals/rentals_screen.dart) ───

// Saisie d'un champ « date et heure » du navigateur : AAAA-MM-JJTHH:MM, lue comme heure du Bénin (UTC+1, sans heure d'été).
const LOCAL_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;

export function beninDateTimeToIso(value: string): string | null {
  return LOCAL_DATETIME.test(value) ? `${value}:00+01:00` : null;
}

// Période de location : début pas avant aujourd'hui (jour du Bénin), fin après le début. null = période valable.
export function rentalPeriodError(startsAt: string, endsAt: string, today: string = beninDateKey()): string | null {
  if (!LOCAL_DATETIME.test(startsAt) || !LOCAL_DATETIME.test(endsAt)) return "Choisissez la date et l’heure de prise et de retour du véhicule.";
  if (startsAt.slice(0, 10) < today) return "La date de début ne peut pas être dans le passé.";
  if (endsAt <= startsAt) return "La fin de location doit être après le début.";
  return null;
}

// Durée affichée (jours entamés, au moins 1), comme l'application. Aucun montant n'est calculé ici.
export function rentalDays(startsAt: string, endsAt: string): number {
  const start = Date.parse(`${startsAt}:00Z`);
  const end = Date.parse(`${endsAt}:00Z`);
  if (Number.isNaN(start) || Number.isNaN(end) || end <= start) return 1;
  return Math.max(1, Math.ceil((end - start) / 3_600_000 / 24));
}

export interface RentalVehicleOffer {
  rental_daily_rate: string | null;
  rental_daily_rate_with_driver?: string | null;
  driver_available: boolean;
  driver_required?: boolean;
}

// Formules proposées pour un véhicule, d'après la Flotte (serveur) : sans chauffeur interdit si le chauffeur est obligatoire.
export function rentalFormulas(vehicle: RentalVehicleOffer) {
  const required = vehicle.driver_required === true;
  return {
    selfDrive: !required,
    withDriver: required || vehicle.driver_available,
    defaultWithDriver: required,
  };
}

// Tarif par jour de la formule, tel que saisi dans la Flotte ; null s'il n'est pas renseigné (jamais de tarif de repli).
export function rentalDailyRate(vehicle: RentalVehicleOffer, withDriver: boolean): string | null {
  const rate = withDriver ? vehicle.rental_daily_rate_with_driver : vehicle.rental_daily_rate;
  return rate === undefined || rate === null || rate === "" ? null : rate;
}

// Couleur de la pastille de statut, comme l'application : confirmée ou en cours = vert, annulée ou refusée = rouge, sinon orange.
export function rentalStatusTone(status: string): "ok" | "danger" | "warn" {
  const value = status.toUpperCase();
  if (value.includes("CONFIRM") || value.includes("APPROVED") || value.includes("ACTIVE")) return "ok";
  if (value.includes("CANCEL") || value.includes("REJECT")) return "danger";
  return "warn";
}

// Accueil de l'espace du personnel qui contient `pathname` (/admin, /guichet, /controleur), sinon le site client.
export function staffSpaceHome(pathname: string): string {
  const space = ["/admin", "/guichet", "/controleur"].find((root) => pathname === root || pathname.startsWith(`${root}/`));
  return space ?? "/";
}

// Points d'embarquement : libellés en question, avec une courte aide.
export const BOARDING_POINT_HELP = "Choisissez l’arrêt exact";
export function boardingFieldLabel(kind: "boarding" | "alighting", city: string): string {
  const place = city.trim() || "votre ville";
  return kind === "boarding" ? `Où montez-vous à ${place} ?` : `Où descendez-vous à ${place} ?`;
}

// Nombre de passagers choisi dans la recherche (1 à 8) : les passagers déjà saisis sont gardés.
export function resizePassengers<T>(current: T[], count: number, blank: (index: number) => T): T[] {
  const wanted = Math.min(8, Math.max(1, Math.trunc(count) || 1));
  if (current.length === wanted) return current;
  if (current.length > wanted) return current.slice(0, wanted);
  return [...current, ...Array.from({ length: wanted - current.length }, (_, i) => blank(current.length + i))];
}

// ─── Dates et heures : toujours à l'heure du Bénin, quel que soit le réglage de l'appareil ───

export const BENIN_TIME_ZONE = "Africa/Porto-Novo";

// Instant venant du serveur (ISO avec fuseau) affiché à l'heure du Bénin.
export function formatBeninDateTime(value: string, options: Intl.DateTimeFormatOptions = { dateStyle: "medium", timeStyle: "short" }): string {
  return new Intl.DateTimeFormat("fr-FR", { ...options, timeZone: BENIN_TIME_ZONE }).format(new Date(value));
}

// Jour calendaire AAAA-MM-JJ (déjà un jour du Bénin) : affiché tel quel, sans glisser d'un jour selon le fuseau de l'appareil.
export function formatDayKey(key: string, options: Intl.DateTimeFormatOptions): string {
  return new Intl.DateTimeFormat("fr-FR", { ...options, timeZone: "UTC" }).format(new Date(`${key}T12:00:00Z`));
}

// ─── Numéro WhatsApp du client : indicatif choisi + numéro local (voyageurs d'autres pays) ───

// Indicatifs proposés au guichet ; « Autre » permet d'en saisir n'importe lequel. Liste à ajuster par l'agence.
export const PHONE_COUNTRY_CODES: Array<{ code: string; label: string }> = [
  { code: "+229", label: "Bénin (+229)" },
  { code: "+228", label: "Togo (+228)" },
  { code: "+234", label: "Nigeria (+234)" },
  { code: "+227", label: "Niger (+227)" },
  { code: "+226", label: "Burkina Faso (+226)" },
  { code: "+233", label: "Ghana (+233)" },
  { code: "+225", label: "Côte d’Ivoire (+225)" },
  { code: "+221", label: "Sénégal (+221)" },
  { code: "+223", label: "Mali (+223)" },
  { code: "+237", label: "Cameroun (+237)" },
  { code: "+241", label: "Gabon (+241)" },
  { code: "+33", label: "France (+33)" },
];

// Numéro international à partir de l'indicatif et du numéro saisi. Un numéro déjà international (+…) est gardé.
// Bénin : le numéro à 10 chiffres garde son 01 (numérotation de 2024). Ailleurs, le 0 initial national est retiré.
// null si l'indicatif ou le numéro ne sont pas valables.
export function internationalNumber(code: string, local: string): string | null {
  const compact = local.replace(/[\s.\-()]/g, "");
  if (/^(\+|00)\d{6,15}$/.test(compact)) return compact.startsWith("00") ? `+${compact.slice(2)}` : compact;
  if (!/^\+\d{1,4}$/.test(code) || !/^\d{4,14}$/.test(compact)) return null;
  const national = code === "+229" ? compact : compact.replace(/^0/, "");
  return `${code}${national}`;
}

// Suivi colis : phrase sur la position du bus (mêmes textes dans l'application).
export function parcelBusText(bus: { departure_at: string; last_stop: string | null; last_confirmed_at: string | null }): string {
  if (bus.last_stop && bus.last_confirmed_at) {
    return `Dernier passage confirmé : ${bus.last_stop}, le ${formatBeninDateTime(bus.last_confirmed_at)}.`;
  }
  return `Aucune arrivée confirmée pour l’instant. Départ prévu le ${formatBeninDateTime(bus.departure_at)}.`;
}

// Rappel « ajoutez votre e-mail » : client connecté sans e-mail vérifié (mêmes textes dans l'application).
export const EMAIL_REMINDER_TEXT = "Ajoutez votre e-mail pour pouvoir récupérer votre compte si vous oubliez votre mot de passe. Sans e-mail, vous devrez contacter l’agence.";
export function needsEmailReminder(user: { role: string; email_verified?: boolean } | null): boolean {
  return Boolean(user && user.role === "CLIENT" && !user.email_verified);
}

// Recherche du guichet : référence AX-… ou téléphone (complet, ou 6 chiffres au moins). Jamais par nom (règle du serveur).
export function counterSearchError(query: string): string | null {
  const text = query.trim();
  if (/^AX-[A-Z0-9-]+$/i.test(text)) return null;
  const digits = text.replace(/[\s.()+-]/g, "");
  if (/^\d{6,}$/.test(digits)) return null;
  return "Saisissez la référence du billet (AX-…) ou le téléphone : au moins 6 chiffres. La recherche par nom n’est pas possible.";
}

// Filtre des listes admin : un jour (par défaut aujourd'hui), une période, ou tous les jours.
export type ListPeriod = { mode: "day" | "period" | "all"; day: string; start: string; end: string };

export function todayPeriod(today: string = beninDateKey()): ListPeriod {
  return { mode: "day", day: today, start: today, end: today };
}

// Paramètres envoyés au serveur (c'est lui qui filtre) ; null si la période saisie est incomplète ou inversée.
export function periodParams(period: ListPeriod, status = ""): string | null {
  const params = new URLSearchParams();
  if (period.mode === "day") {
    if (!period.day) return null;
    params.set("start", period.day);
  } else if (period.mode === "period") {
    if (!period.start || !period.end || period.end < period.start) return null;
    params.set("start", period.start);
    params.set("end", period.end);
  }
  if (status) params.set("status", status);
  const text = params.toString();
  return text ? `?${text}` : "";
}

// Demande de location : champs obligatoires, mêmes libellés et messages que le serveur et l'application.
export type RentalIdentity = { renter_full_name: string; cip_number: string; licence_number: string; zone: string };
export const RENTAL_IDENTITY_LABELS: Record<keyof RentalIdentity, string> = {
  renter_full_name: "Nom et prénoms",
  cip_number: "Numéro du CIP",
  licence_number: "Numéro du permis de conduire",
  zone: "Zone de circulation",
};
const RENTAL_IDENTITY_MESSAGES: Record<keyof RentalIdentity, string> = {
  renter_full_name: "Indiquez le nom et les prénoms.",
  cip_number: "Indiquez le numéro du CIP.",
  licence_number: "Indiquez le numéro du permis de conduire.",
  zone: "Choisissez la zone de circulation du véhicule.",
};

export function rentalIdentityError(values: RentalIdentity): string | null {
  for (const key of Object.keys(RENTAL_IDENTITY_MESSAGES) as Array<keyof RentalIdentity>) {
    if (!String(values[key] || "").trim()) return RENTAL_IDENTITY_MESSAGES[key];
  }
  return null;
}

// Montée à un arrêt intermédiaire : mot pour mot le texte de l'application (trip_results_screen.dart).
export const ONBOARD_ONLY_MESSAGE = "Montée à bord, auprès du contrôleur : cette montée ne s’achète pas en ligne.";
