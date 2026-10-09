// Réservation en cours, conservée dans le navigateur pour survivre à la redirection vers la page de paiement,
// à un rechargement ou à une fermeture d'onglet.
// Aucune donnée personnelle : identifiant de la réservation, jeton d'accès (invité seulement),
// identifiants techniques du paiement, échéance.
const KEY = "axis_guest_booking";
const LIFETIME_MS = 24 * 60 * 60 * 1000;

export type GuestBooking = {
  id: number;
  // Jeton d'une réservation faite sans compte ; null quand un client connecté a réservé.
  token: string | null;
  expiresAt: number;
  paymentMethod?: number;
  transactionId?: string;
  paymentUrl?: string;
};

export function loadGuestBooking(): GuestBooking | null {
  if (typeof window === "undefined") return null;
  try {
    const stored = JSON.parse(window.localStorage.getItem(KEY) ?? "null") as GuestBooking | null;
    if (!stored || typeof stored.id !== "number" || !(stored.expiresAt > Date.now())) {
      window.localStorage.removeItem(KEY);
      return null;
    }
    return { ...stored, token: typeof stored.token === "string" ? stored.token : null };
  } catch {
    return null;
  }
}

export function saveGuestBooking(id: number, token: string | null) {
  window.localStorage.setItem(KEY, JSON.stringify({ id, token, expiresAt: Date.now() + LIFETIME_MS } satisfies GuestBooking));
}

export function rememberGuestPayment(paymentMethod: number, transactionId: string, paymentUrl?: string | null) {
  const stored = loadGuestBooking();
  if (stored) window.localStorage.setItem(KEY, JSON.stringify({ ...stored, paymentMethod, transactionId, paymentUrl: paymentUrl ?? undefined }));
}

export function clearGuestBooking() {
  if (typeof window !== "undefined") window.localStorage.removeItem(KEY);
}

// En-têtes d'accès à la réservation : le jeton pour un invité, rien pour un client connecté (son compte suffit).
export function bookingAccessHeaders(stored: { token: string | null }): Record<string, string> {
  return stored.token ? { "X-Booking-Token": stored.token } : {};
}
