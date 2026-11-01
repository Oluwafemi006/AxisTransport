import { nextPagePath } from "./portal-rules";

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

export function setTokens(access: string, refresh: string) {
  window.localStorage.setItem("axis_access_token", access);
  window.localStorage.setItem("axis_refresh_token", refresh);
}

export function clearTokens() {
  window.localStorage.removeItem("axis_access_token");
  window.localStorage.removeItem("axis_refresh_token");
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

export async function apiFetch<T>(path: string, init: RequestInit = {}, authenticated = true): Promise<T> {
  const headers = new Headers(init.headers);
  if (!(init.body instanceof FormData)) headers.set("Content-Type", "application/json");
  if (authenticated) {
    const token = getAccessToken();
    if (token) headers.set("Authorization", `Bearer ${token}`);
  }
  const response = await fetch(`${API_URL}${path}`, { ...init, headers, cache: "no-store" });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new ApiError(errorMessage(payload), response.status, payload);
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

export async function requestPasswordReset(email: string) {
  return await apiFetch<{ detail: string }>("/auth/password-reset/request/", { method: "POST", body: JSON.stringify({ email }) }, false);
}

export async function confirmPasswordReset(email: string, code: string, password: string) {
  return await apiFetch<{ detail: string }>("/auth/password-reset/confirm/", { method: "POST", body: JSON.stringify({ email, code, password }) }, false);
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
  return new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

