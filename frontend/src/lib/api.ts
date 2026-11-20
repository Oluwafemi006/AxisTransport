import { formatBeninDateTime, nextPagePath, shareInFlight, writeKey } from "./portal-rules";
import { ACTIVITY_KEY, EXPIRED_KEY, SESSION_EXPIRED_EVENT, refreshedTokens, shouldRefresh } from "./session";
import type { User } from "./types";

// Adresse de l'API (se termine par /api/v1). Aucune valeur par défaut : voir DEPLOY.md.
export const API_URL = (process.env.NEXT_PUBLIC_API_URL ?? "").replace(/\/$/, "");

export class ApiError extends Error {
  status: number;
  details: unknown;

  constructor(message: string, status: number, details: unknown) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export function getAccessToken() {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem("axis_access_token");
}

export function getRefreshToken() {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem("axis_refresh_token");
}

export function setTokens(access: string, refresh: string) {
  window.localStorage.setItem("axis_access_token", access);
  window.localStorage.setItem("axis_refresh_token", refresh);
  window.localStorage.removeItem(EXPIRED_KEY);
  touchActivity();
}

export function clearTokens() {
  window.localStorage.removeItem("axis_access_token");
  window.localStorage.removeItem("axis_refresh_token");
}

// Dernière activité (clic, frappe, requête authentifiée), partagée entre les onglets du même navigateur.
export function touchActivity() {
  if (typeof window === "undefined") return;
  try { window.localStorage.setItem(ACTIVITY_KEY, String(Date.now())); } catch { /* stockage indisponible : pas de compteur */ }
}

// Session fermée par le site (renouvellement refusé ou inactivité) : les portails affichent « Session expirée ».
export function markSessionExpired() {
  if (typeof window === "undefined") return;
  clearTokens();
  try { window.localStorage.setItem(EXPIRED_KEY, "1"); } catch { /* idem */ }
  window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
}

export function sessionWasExpired() {
  if (typeof window === "undefined") return false;
  try { return window.localStorage.getItem(EXPIRED_KEY) === "1"; } catch { return false; }
}

// Renouvellement du jeton d'accès : une seule requête à la fois, partagée par tous les appels en attente.
// Le serveur fait tourner le jeton de renouvellement : le nouveau remplace l'ancien.
// Résultat : true (renouvelé), false (refusé par le serveur : session terminée), null (réseau : rien n'est décidé).
let refreshing: Promise<boolean | null> | null = null;

export function refreshAccessToken(): Promise<boolean | null> {
  if (!refreshing) {
    refreshing = (async () => {
      const refresh = getRefreshToken();
      if (!refresh) return false;
      try {
        const response = await fetch(`${API_URL}/auth/token/refresh/`, {
          method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refresh }), cache: "no-store",
        });
        if (!response.ok) return false;
        const tokens = refreshedTokens(await response.json().catch(() => null));
        if (!tokens) return false;
        setTokens(tokens.access, tokens.refresh ?? refresh);
        return true;
      } catch {
        // Réseau coupé : rien n'est décidé, la requête d'origine échoue et pourra être rejouée.
        return null;
      } finally {
        refreshing = null;
      }
    })();
  }
  return refreshing;
}

function errorMessage(payload: unknown) {
  if (typeof payload === "string") return payload;
  if (payload && typeof payload === "object") {
    const record = payload as Record<string, unknown>;
    const detail = record.detail;
    if (typeof detail === "string") return detail;
    const first = Object.values(record)[0];
    if (Array.isArray(first) && typeof first[0] === "string") return first[0];
    if (typeof first === "string") return first;
  }
  return "Une erreur est survenue.";
}

const pendingWrites = new Map<string, Promise<unknown>>();

export function apiFetch<T>(path: string, init: RequestInit = {}, authenticated = true): Promise<T> {
  return shareInFlight(pendingWrites, writeKey(init.method, path, init.body), () => send<T>(path, init, authenticated));
}

async function send<T>(path: string, init: RequestInit, authenticated: boolean, retried = false): Promise<T> {
  const headers = new Headers(init.headers);
  if (!(init.body instanceof FormData)) headers.set("Content-Type", "application/json");
  const token = authenticated ? getAccessToken() : null;
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
    touchActivity();
  }
  const response = await fetch(`${API_URL}${path}`, { ...init, headers, cache: "no-store" });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) {
    // Jeton d'accès périmé : renouvellement (une seule fois), puis la même requête est rejouée.
    if (shouldRefresh(response.status, Boolean(token), Boolean(getRefreshToken()), retried)) {
      const renewed = await refreshAccessToken();
      if (renewed) return send<T>(path, init, authenticated, true);
      // Renouvellement refusé par le serveur (jeton expiré, session fermée) : la session est terminée.
      if (renewed === false) markSessionExpired();
    }
    throw new ApiError(errorMessage(payload), response.status, payload);
  }
  return payload as T;
}

export async function apiList<T>(path: string, authenticated = true): Promise<T[]> {
  const rows: T[] = [];
  let current: string | null = path;
  while (current) {
    const payload: T[] | { results: T[]; next?: string | null } = await apiFetch(current, {}, authenticated);
    if (Array.isArray(payload)) return payload;
    rows.push(...payload.results);
    current = nextPagePath(current, payload.next);
  }
  return rows;
}

export async function login(username: string, password: string) {
  const tokens = await apiFetch<{ access: string; refresh: string }>(
    "/auth/token/",
    { method: "POST", body: JSON.stringify({ username, password }) },
    false,
  );
  setTokens(tokens.access, tokens.refresh);
  return tokens;
}

export interface StaffInvitationVerification {
  email: string;
  group: string;
  role: string;
  role_label: string;
  expires_at: string;
}

export interface StaffInvitationAcceptResponse {
  detail: string;
  username: string;
  role: string;
  group: string;
}

export async function updateMyEmail(email: string) {
  return await apiFetch<User>("/auth/me/", { method: "PATCH", body: JSON.stringify({ email }) });
}

/** Envoi du code de vérification : le serveur dit clairement si l'e-mail n'est pas parti (jamais « envoyé » à tort). */
export async function sendEmailCode() {
  return await apiFetch<{ detail: string; email_sent?: boolean }>("/auth/email/send-code/", { method: "POST" });
}

export async function verifyEmailCode(code: string) {
  return await apiFetch<{ detail: string; user: User }>("/auth/email/verify/", { method: "POST", body: JSON.stringify({ code }) });
}

/** Les autres sessions sont fermées par le serveur ; celle-ci garde les nouveaux jetons. */
export async function changeMyPassword(currentPassword: string, newPassword: string) {
  const result = await apiFetch<{ detail: string; access: string; refresh: string }>("/auth/password/change/", {
    method: "POST",
    body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
  });
  setTokens(result.access, result.refresh);
  return result;
}

export async function requestPasswordReset(email: string) {
  return await apiFetch<{ detail: string }>("/auth/password-reset/request/", { method: "POST", body: JSON.stringify({ email }) }, false);
}

// Lien reçu par e-mail (ou transmis par l'agence) : vérification, puis choix du nouveau mot de passe.
export async function checkPasswordResetLink(token: string) {
  return await apiFetch<{ valid: boolean }>(`/auth/password-reset/link/?token=${encodeURIComponent(token)}`, {}, false);
}

export async function submitPasswordResetLink(token: string, password: string) {
  return await apiFetch<{ detail: string }>("/auth/password-reset/link/", { method: "POST", body: JSON.stringify({ token, password }) }, false);
}

export async function verifyStaffInvitation(token: string): Promise<StaffInvitationVerification> {
  return await apiFetch<StaffInvitationVerification>(
    `/auth/invite/accept/?token=${encodeURIComponent(token)}`,
    { method: "GET" },
    false,
  );
}

export async function acceptStaffInvitation(token: string, password: string): Promise<StaffInvitationAcceptResponse> {
  return await apiFetch<StaffInvitationAcceptResponse>(
    "/auth/invite/accept/",
    {
      method: "POST",
      body: JSON.stringify({ token, password }),
    },
    false,
  );
}


export function money(amount: string | number | null, currency = "XOF") {
  if (amount === null || amount === undefined || amount === "") return "À configurer";
  // Le franc CFA s'affiche « FCFA », jamais avec son code « XOF ».
  if (currency === "XOF") {
    return `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(Number(amount))} FCFA`;
  }
  return new Intl.NumberFormat("fr-FR", { style: "currency", currency, maximumFractionDigits: 0 }).format(
    Number(amount),
  );
}

export function formatDate(value: string) {
  // Heure du Bénin partout (et non celle réglée sur l'appareil).
  return formatBeninDateTime(value);
}

