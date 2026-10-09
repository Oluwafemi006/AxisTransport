// Réservation d'un invité, conservée dans le navigateur pour survivre à un rechargement ou à une fermeture d'onglet.
// Aucune donnée personnelle : identifiant et jeton de la réservation, identifiants techniques du paiement, échéance.
const KEY = "axis_guest_booking";
const LIFETIME_MS = 24 * 60 * 60 * 1000;

export type GuestBooking = {
  id: number;
  token: string;
  expiresAt: number;
  paymentMethod?: number;
  transactionId?: string;
};

export function loadGuestBooking(): GuestBooking | null {
  if (typeof window === "undefined") return null;
  try {
    const stored = JSON.parse(window.localStorage.getItem(KEY) ?? "null") as GuestBooking | null;
    if (!stored || typeof stored.id !== "number" || typeof stored.token !== "string" || !(stored.expiresAt > Date.now())) {
      window.localStorage.removeItem(KEY);
      return null;
    }
    return stored;
  } catch {
    return null;
  }
}

export function saveGuestBooking(id: number, token: string) {
  window.localStorage.setItem(KEY, JSON.stringify({ id, token, expiresAt: Date.now() + LIFETIME_MS } satisfies GuestBooking));
}

export function rememberGuestPayment(paymentMethod: number, transactionId: string) {
  const stored = loadGuestBooking();
  if (stored) window.localStorage.setItem(KEY, JSON.stringify({ ...stored, paymentMethod, transactionId }));
}

export function clearGuestBooking() {
  if (typeof window !== "undefined") window.localStorage.removeItem(KEY);
}
