// Espace client : l'onglet et la recherche (départ, arrivée, date, passagers) vivent dans l'adresse de la page,
// pour que le rechargement et le bouton retour du navigateur ramènent au même endroit. Règles pures, testées par
// tests/search-url.test.mjs.

export const CLIENT_TABS = ["accueil", "billets", "colis", "location", "profil"] as const;
export type ClientTabKey = (typeof CLIENT_TABS)[number];

export type ClientLocation = {
  tab: ClientTabKey;
  origin: string;
  destination: string;
  date: string;
  passengers: number;
};

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^\d+$/;

export function readClientLocation(search: string): ClientLocation {
  const params = new URLSearchParams(search);
  const tab = params.get("onglet");
  const passengers = Number(params.get("passagers"));
  return {
    tab: (CLIENT_TABS as readonly string[]).includes(tab ?? "") ? (tab as ClientTabKey) : "accueil",
    origin: ID.test(params.get("depart") ?? "") ? (params.get("depart") as string) : "",
    destination: ID.test(params.get("arrivee") ?? "") ? (params.get("arrivee") as string) : "",
    date: DAY.test(params.get("date") ?? "") ? (params.get("date") as string) : "",
    passengers: Number.isInteger(passengers) && passengers >= 1 && passengers <= 8 ? passengers : 1,
  };
}

// Adresse d'un état : seuls les champs utiles sont écrits (accueil sans recherche = adresse nue).
export function clientLocationSearch(location: ClientLocation): string {
  const params = new URLSearchParams();
  if (location.tab !== "accueil") params.set("onglet", location.tab);
  if (location.origin && location.destination && location.date) {
    params.set("depart", location.origin);
    params.set("arrivee", location.destination);
    params.set("date", location.date);
    params.set("passagers", String(location.passengers));
  }
  const text = params.toString();
  return text ? `?${text}` : "";
}

// Recherche complète (de quoi afficher le résumé au lieu de redemander le trajet).
export function hasCompleteSearch(location: Pick<ClientLocation, "origin" | "destination" | "date">): boolean {
  return Boolean(location.origin && location.destination && location.date && location.origin !== location.destination);
}

// Jour précédent ou suivant (AAAA-MM-JJ), sans passer par le fuseau de l'appareil.
export function shiftDayKey(day: string, delta: number): string {
  const date = new Date(`${day}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
}

// « Parakou → Savè · 19/11 · 1 passager »
export function searchSummary(origin: string, destination: string, day: string, passengers: number): string {
  const [, month, date] = day.split("-");
  return `${origin} → ${destination} · ${date}/${month} · ${passengers} passager${passengers > 1 ? "s" : ""}`;
}

// Étapes visibles de la réservation : Trajet, Places et passagers, Paiement, Billet.
export const BOOKING_STEPS = ["Trajet", "Places et passagers", "Paiement", "Billet"] as const;
export function bookingStep(state: { tripChosen: boolean; held: boolean; issued: boolean }): 1 | 2 | 3 | 4 {
  if (state.issued) return 4;
  if (state.held) return 3;
  return state.tripChosen ? 2 : 1;
}
