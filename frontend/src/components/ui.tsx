import { ReactNode } from "react";
import { Brand } from "./brand";
import type { User } from "@/lib/types";

export type Tone = "blue" | "green" | "amber" | "red" | "grey";
export type NoticeState = { text: string; tone: "ok" | "error" | "info" } | null;

// Noms de classes écrits en entier : Tailwind retire du CSS ceux qu'il ne trouve pas tels quels dans le code.
const badgeClasses: Record<Tone, string> = { blue: "badge", green: "badge badge-green", amber: "badge badge-amber", red: "badge badge-red", grey: "badge badge-grey" };
const noticeClasses = { info: "notice", ok: "notice notice-ok", error: "notice notice-error" };

export function StatusBadge({ children, tone = "blue" }: { children: ReactNode; tone?: Tone }) {
  return <span className={badgeClasses[tone]}>{children}</span>;
}

const tripTones: Record<string, Tone> = { SCHEDULED: "blue", BOARDING: "amber", IN_PROGRESS: "amber", COMPLETED: "green", CANCELLED: "red" };
const ticketTones: Record<string, Tone> = { HELD: "amber", PAID: "blue", ISSUED: "green", CHECKED: "green", COMPLETED: "green", CANCELLED: "red", REFUNDED: "grey", EXPIRED: "grey" };

export function tripTone(status: string): Tone {
  return tripTones[status] ?? "blue";
}

export function ticketTone(status: string): Tone {
  return ticketTones[status] ?? "blue";
}

export function EmptyState({ title, text }: { title: string; text: string }) {
  return (
    <div className="empty">
      <b>{title}</b>
      <span>{text}</span>
    </div>
  );
}

export function Loading() {
  return <div className="skeleton" role="status" aria-live="polite">Chargement…</div>;
}

export function Notice({ notice, className = "mt-4" }: { notice: NoticeState; className?: string }) {
  if (!notice) return null;
  return (
    <p className={`${noticeClasses[notice.tone]} ${className}`} role={notice.tone === "error" ? "alert" : "status"}>
      {notice.text}
    </p>
  );
}

export function SectionHeading({ eyebrow, title, action }: { eyebrow?: string; title: string; action?: ReactNode }) {
  return (
    <div className="mb-4 flex items-end justify-between gap-4">
      <div>
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h2>{title}</h2>
      </div>
      {action}
    </div>
  );
}

function logout() {
  window.localStorage.removeItem("axis_access_token");
  window.localStorage.removeItem("axis_refresh_token");
  window.location.reload();
}

// En-tête commun aux portails équipe : logo du site, onglets éventuels, compte connecté.
export function StaffShell<Key extends string>({ user, tabs, current, onTab, children }: {
  user: User | null;
  tabs?: Array<[Key, string]>;
  current?: Key;
  onTab?: (key: Key) => void;
  children: ReactNode;
}) {
  return (
    <div className="staff">
      <header>
        <div className="wrap nav">
          <Brand />
          <div className="sp" />
          {user && (
            <p className="staff-user">
              <b>{[user.first_name, user.last_name].filter(Boolean).join(" ") || user.username}</b>
              {user.role_display}
            </p>
          )}
          <button className="btn s" onClick={logout}>Déconnexion</button>
        </div>
        {tabs && (
          <nav className="wrap staff-tabs" aria-label="Sections">
            {tabs.map(([key, label]) => (
              <button key={key} className={current === key ? "on" : ""} aria-current={current === key ? "page" : undefined} onClick={() => onTab?.(key)}>
                {label}
              </button>
            ))}
          </nav>
        )}
      </header>
      <main className="wrap staff-main">{children}</main>
    </div>
  );
}

export function StaffTitle({ eyebrow, title, action }: { eyebrow: string; title: string; action?: ReactNode }) {
  return (
    <div className="staff-title">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
      </div>
      {action}
    </div>
  );
}

// Page de connexion commune aux trois portails.
export function StaffLogin({ children, error }: { children: ReactNode; error?: string }) {
  return (
    <div className="staff">
      <header>
        <div className="wrap nav">
          <Brand />
        </div>
      </header>
      <main className="wrap staff-login">
        {children}
        {error && <Notice notice={{ text: error, tone: "error" }} className="w-full max-w-[420px]" />}
      </main>
    </div>
  );
}

export function AccessDenied({ area }: { area: string }) {
  return (
    <div className="staff">
      <header>
        <div className="wrap nav">
          <Brand />
          <div className="sp" />
          <button className="btn s" onClick={logout}>Déconnexion</button>
        </div>
      </header>
      <main className="wrap staff-login">
        <section className="login-card text-center">
          <p className="eyebrow text-red-700">Accès refusé</p>
          <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Espace réservé à {area}</h1>
          <p className="mt-3 text-sm leading-6 text-slate-600">Votre compte est connecté, mais son rôle ne permet pas d’ouvrir cette interface.</p>
          <a className="primary-button mt-6" href="/">Retour à l’espace client</a>
        </section>
      </main>
    </div>
  );
}
