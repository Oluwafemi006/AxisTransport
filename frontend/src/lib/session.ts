// Règles de session du site, sans dépendance : testées par tests/session.test.mjs.
// Le serveur garde ses durées (jeton d'accès 30 min, renouvellement 7 jours) ; ici seulement la conduite du site.

// Déconnexion automatique après inactivité (postes de guichet partagés). Une activité (clic, frappe, requête) remet le compteur à zéro.
export const INACTIVITY_LIMIT_MS = 30 * 60 * 1000;
// Fréquence de la vérification d'inactivité.
export const INACTIVITY_CHECK_MS = 30 * 1000;
export const SESSION_EXPIRED_MESSAGE = "Session expirée : reconnectez-vous pour continuer.";

export const ACTIVITY_KEY = "axis_last_activity";
export const EXPIRED_KEY = "axis_session_expired";
export const SESSION_EXPIRED_EVENT = "axis:session-expired";
export const ACTIVITY_EVENTS = ["pointerdown", "keydown", "touchstart"] as const;

// Inactivité dépassée ? Sans horodatage connu, non : le compteur part de maintenant.
export function inactivityExpired(lastActivityAt: number | null, now: number, limitMs = INACTIVITY_LIMIT_MS): boolean {
  if (lastActivityAt === null || !Number.isFinite(lastActivityAt)) return false;
  return now - lastActivityAt >= limitMs;
}

// Un 401 d'une requête authentifiée se renouvelle une seule fois, et seulement si un jeton de renouvellement existe.
export function shouldRefresh(status: number, authenticated: boolean, hasRefreshToken: boolean, alreadyRetried: boolean): boolean {
  return status === 401 && authenticated && hasRefreshToken && !alreadyRetried;
}

// Réponse du renouvellement : jeton d'accès obligatoire, nouveau jeton de renouvellement si le serveur en renvoie un (rotation).
export function refreshedTokens(payload: unknown): { access: string; refresh: string | null } | null {
  if (!payload || typeof payload !== "object") return null;
  const record = payload as Record<string, unknown>;
  if (typeof record.access !== "string" || !record.access) return null;
  return { access: record.access, refresh: typeof record.refresh === "string" && record.refresh ? record.refresh : null };
}

// Lecture tolérante de l'horodatage d'activité conservé (localStorage, partagé entre onglets).
export function parseActivity(raw: string | null): number | null {
  if (raw === null || raw === "") return null;
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : null;
}
