// Vente Mobile Money par le personnel : espace d'origine, état du paiement au retour de FedaPay, vente en attente.
// Règles pures testées par tests/staff-sale.test.mjs ; le reste lit ou écrit le stockage du navigateur.

// Même liste fixe que le serveur (backend/apps/core/payments.py, STAFF_RETURN_SPACES) : aucune adresse libre.
export const STAFF_SPACES = ["guichet", "controleur", "admin"] as const;
export type StaffSpace = (typeof STAFF_SPACES)[number];

export function isStaffSpace(value: unknown): value is StaffSpace {
  return typeof value === "string" && (STAFF_SPACES as readonly string[]).includes(value);
}

// Accueil de chaque espace : la page où l'agent revient après une vente.
export function staffSpaceHomePath(space: StaffSpace): string {
  return `/${space}`;
}

export type ReturnState = "attente" | "paye" | "echoue" | "expire";

// État affiché au retour de FedaPay. Le statut de la réservation vient du serveur et décide :
// confirmée = payé ; expirée ou annulée = place libérée. Le statut renvoyé par FedaPay dans l'adresse
// ne sert qu'à signaler un refus (jamais à déclarer un paiement réussi).
export function staffReturnState(bookingStatus: string | null, providerStatus: string | null): ReturnState {
  if (bookingStatus === "CONFIRMED") return "paye";
  if (bookingStatus === "EXPIRED" || bookingStatus === "CANCELLED") return "expire";
  if (providerStatus && !["approved", "pending"].includes(providerStatus.toLowerCase())) return "echoue";
  return "attente";
}

export const RETURN_MESSAGES: Record<ReturnState, { title: string; text: string }> = {
  attente: {
    title: "Paiement en attente",
    text: "Le client doit confirmer le paiement sur son téléphone. Le billet est émis dès que le paiement est confirmé.",
  },
  paye: { title: "Paiement confirmé", text: "Le billet est émis." },
  echoue: {
    title: "Paiement non abouti",
    text: "Le paiement a été refusé ou annulé. Aucun billet n’est émis. La place reste tenue jusqu’à l’expiration : vous pouvez relancer le paiement depuis l’écran des ventes.",
  },
  expire: {
    title: "Vente expirée",
    text: "La place n’est plus tenue : le délai est dépassé ou la vente a été annulée. Aucun billet n’est émis.",
  },
};

// Nouvelles tentatives de vérification au retour : toutes les 5 s pendant 2 min au plus.
export const RETURN_POLL_MS = 5000;
export const RETURN_POLL_LIMIT_MS = 120000;

export function isFinalState(state: ReturnState): boolean {
  return state === "paye" || state === "expire";
}

// Lien vers l'application Android (axistransport://) : seulement pour un client sur Android.
export function showAndroidAppLink(userAgent: string, staff: boolean): boolean {
  return !staff && /android/i.test(userAgent);
}

// ─── Vente en attente, gardée dans ce navigateur (onglet de paiement ouvert à côté) ──────────────

export type PendingStaffSale = {
  bookingId: number;
  paymentMethod: number;
  transactionId: string;
  paymentUrl: string | null;
  space: StaffSpace;
  savedAt: number;
};

const SALE_KEY = "axis_staff_sale";
// Résultat écrit par la page de retour : la fenêtre d'origine l'apprend par l'événement « storage ».
export const SALE_RESULT_KEY = "axis_staff_sale_result";

export function parsePendingSale(raw: string | null): PendingStaffSale | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<PendingStaffSale>;
    if (typeof value.bookingId !== "number" || typeof value.paymentMethod !== "number" || typeof value.transactionId !== "string" || !isStaffSpace(value.space)) return null;
    return {
      bookingId: value.bookingId,
      paymentMethod: value.paymentMethod,
      transactionId: value.transactionId,
      paymentUrl: typeof value.paymentUrl === "string" ? value.paymentUrl : null,
      space: value.space,
      savedAt: typeof value.savedAt === "number" ? value.savedAt : 0,
    };
  } catch {
    return null;
  }
}

export function loadPendingSale(): PendingStaffSale | null {
  if (typeof window === "undefined") return null;
  try { return parsePendingSale(window.localStorage.getItem(SALE_KEY)); } catch { return null; }
}

export function savePendingSale(sale: Omit<PendingStaffSale, "savedAt">) {
  try { window.localStorage.setItem(SALE_KEY, JSON.stringify({ ...sale, savedAt: Date.now() })); } catch { /* stockage indisponible */ }
}

export function clearPendingSale(bookingId?: number) {
  try {
    const current = loadPendingSale();
    if (bookingId === undefined || current?.bookingId === bookingId) window.localStorage.removeItem(SALE_KEY);
  } catch { /* stockage indisponible */ }
}

export function announceSaleResult(bookingId: number, state: ReturnState) {
  try { window.localStorage.setItem(SALE_RESULT_KEY, JSON.stringify({ bookingId, state, at: Date.now() })); } catch { /* idem */ }
}

export function parseSaleResult(raw: string | null): { bookingId: number; state: ReturnState } | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as { bookingId?: unknown; state?: unknown };
    if (typeof value.bookingId !== "number" || !["attente", "paye", "echoue", "expire"].includes(String(value.state))) return null;
    return { bookingId: value.bookingId, state: value.state as ReturnState };
  } catch {
    return null;
  }
}
