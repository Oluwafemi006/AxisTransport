// PWA par espace et paiement Mobile Money embarqué (FedaPay Checkout.js).
// Les règles pures (sans navigateur) sont testées par tests/pwa.test.mjs ; le reste touche au DOM.

// Clé publique FedaPay, lue à la compilation du site (NEXT_PUBLIC_*). Vide = paiement par redirection.
export const FEDAPAY_PUBLIC_KEY = (process.env.NEXT_PUBLIC_FEDAPAY_PUBLIC_KEY ?? "").trim();
export const FEDAPAY_CHECKOUT_SCRIPT = "https://cdn.fedapay.com/checkout.js?v=1.1.7";

export const PAYMENT_DISMISSED_MESSAGE =
  "Paiement non terminé. Reprenez le paiement, ou vérifiez-le si vous avez déjà payé.";
export const PAYMENT_EMBEDDED_UNAVAILABLE_MESSAGE = "Redirection vers la page de paiement…";

// Espaces installables séparément : chaque portail déclare son manifeste et sa portée.
export const SPACES = {
  client: { scope: "/", manifest: "/manifest.webmanifest" },
  admin: { scope: "/admin", manifest: "/manifest-admin.webmanifest" },
  guichet: { scope: "/guichet", manifest: "/manifest-guichet.webmanifest" },
  controleur: { scope: "/controleur", manifest: "/manifest-controleur.webmanifest" },
} as const;

type CheckoutLike = { transaction_id: string; payment_url: string | null; simulated: boolean };

// Paiement dans la page (sans quitter la PWA) : clé publique présente, transaction FedaPay réelle
// créée par notre serveur (identifiant numérique), et une page de paiement de repli existe.
export function embeddedPaymentAvailable(publicKey: string, checkout: CheckoutLike | null | undefined): boolean {
  if (!checkout || !publicKey.trim()) return false;
  if (checkout.simulated || !checkout.payment_url) return false;
  return /^\d+$/.test(checkout.transaction_id);
}

export type DialogOutcome = "completed" | "dismissed";

// Fin de la boîte de dialogue FedaPay : `reason` est comparé à la constante CHECKOUT_COMPLETED du script.
// Toute autre valeur (fermeture, inconnue) vaut « non terminé » : le serveur reste le seul à confirmer.
export function paymentDialogOutcome(reason: unknown, completedReason: unknown): DialogOutcome {
  if (completedReason === undefined || completedReason === null) return "dismissed";
  return reason === completedReason ? "completed" : "dismissed";
}

// Anciens service workers enregistrés sur tout le site (portée « / ») : à retirer pour qu'un client
// ou un administrateur ne reçoive plus la page du contrôleur hors ligne.
export function legacyServiceWorkerScopes(scopes: string[], origin: string): string[] {
  const root = `${origin.replace(/\/$/, "")}/`;
  return scopes.filter((scope) => scope === root);
}

// Vérification automatique au retour au premier plan : pas plus d'une fois toutes les `minGapMs`.
export function shouldAutoVerify(lastAt: number | null, now: number, minGapMs = 5000): boolean {
  return lastAt === null || now - lastAt >= minGapMs;
}

// ─── Navigateur ──────────────────────────────────────────────────────────────

type FedaPayWidget = { open: () => void };
type FedaPayGlobal = {
  init: (options: Record<string, unknown>) => FedaPayWidget;
  CHECKOUT_COMPLETED?: unknown;
  DIALOG_DISMISSED?: unknown;
};

declare global {
  interface Window {
    FedaPay?: FedaPayGlobal;
  }
}

let scriptPromise: Promise<FedaPayGlobal | null> | null = null;

// Charge le script FedaPay une seule fois ; null si le réseau ou le navigateur l'empêche (repli : redirection).
export function loadFedaPayCheckout(): Promise<FedaPayGlobal | null> {
  if (typeof window === "undefined") return Promise.resolve(null);
  if (window.FedaPay) return Promise.resolve(window.FedaPay);
  if (!scriptPromise) {
    scriptPromise = new Promise((resolve) => {
      const script = document.createElement("script");
      script.src = FEDAPAY_CHECKOUT_SCRIPT;
      script.async = true;
      script.onload = () => resolve(window.FedaPay ?? null);
      script.onerror = () => { scriptPromise = null; resolve(null); };
      document.head.appendChild(script);
    });
  }
  return scriptPromise;
}

// Ouvre la boîte de dialogue FedaPay sur une transaction déjà créée par notre serveur.
// Résout « completed » ou « dismissed » ; null si le script n'a pas pu s'ouvrir (le portail redirige alors).
export async function openEmbeddedPayment(publicKey: string, transactionId: string): Promise<DialogOutcome | null> {
  const fedapay = await loadFedaPayCheckout();
  if (!fedapay) return null;
  return new Promise((resolve) => {
    try {
      const widget = fedapay.init({
        public_key: publicKey,
        transaction: { id: Number(transactionId) },
        locale: "fr",
        onComplete: (response: { reason?: unknown }) => resolve(paymentDialogOutcome(response?.reason, fedapay.CHECKOUT_COMPLETED)),
      });
      widget.open();
    } catch {
      resolve(null);
    }
  });
}

// Retire les anciens enregistrements à portée « / » (voir legacyServiceWorkerScopes).
export async function unregisterLegacyServiceWorkers(): Promise<void> {
  if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
  try {
    const registrations = await navigator.serviceWorker.getRegistrations();
    const legacy = legacyServiceWorkerScopes(registrations.map((item) => item.scope), window.location.origin);
    await Promise.all(registrations.filter((item) => legacy.includes(item.scope)).map((item) => item.unregister()));
  } catch {
    // Sans service worker utilisable, le site fonctionne en ligne comme avant.
  }
}

// Le seul service worker du site : espace contrôleur, limité à sa portée.
export async function registerControllerServiceWorker(): Promise<void> {
  if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
  await unregisterLegacyServiceWorkers();
  try {
    await navigator.serviceWorker.register("/sw.js", { scope: SPACES.controleur.scope });
  } catch {
    // Hors ligne indisponible : le contrôle reste possible en ligne.
  }
}
