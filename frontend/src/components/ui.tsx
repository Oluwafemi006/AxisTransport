"use client";

import { ForcedPasswordChange } from "./forced-password-change";
import { ReactNode, createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { Brand } from "./brand";
import { actionErrorText } from "@/lib/portal-rules";
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

// ─── Retour des actions du portail ───────────────────────────────────────────
// Un seul composant pour toutes les actions d'écriture : message fixe dans un coin de l'écran (visible même
// en bas de page), succès 6 s, erreur 15 s, fermable. Une erreur n'est jamais affichée comme un succès.

type Feedback = { id: number; text: string; tone: "ok" | "error" | "info" };
type ActionFeedback = {
  success: (text: string) => void;
  info: (text: string) => void;
  failure: (reason: unknown, failed: string) => void;
};

const FEEDBACK_DURATION = { ok: 6000, info: 8000, error: 15000 } as const;
const ActionFeedbackContext = createContext<ActionFeedback | null>(null);

export function ActionFeedbackProvider({ children }: { children: ReactNode }) {
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  const counter = useRef(0);

  const show = useCallback((text: string, tone: Feedback["tone"]) => {
    counter.current += 1;
    setFeedback({ id: counter.current, text, tone });
  }, []);

  useEffect(() => {
    if (!feedback) return;
    const timer = window.setTimeout(() => setFeedback((current) => (current?.id === feedback.id ? null : current)), FEEDBACK_DURATION[feedback.tone]);
    return () => window.clearTimeout(timer);
  }, [feedback]);

  const value = useRef<ActionFeedback>({
    success: (text) => show(text, "ok"),
    info: (text) => show(text, "info"),
    failure: (reason, failed) => show(actionErrorText(reason, failed), "error"),
  }).current;

  return (
    <ActionFeedbackContext.Provider value={value}>
      {children}
      <div className="action-feedback" aria-live="polite">
        {feedback && (
          <p key={feedback.id} className={noticeClasses[feedback.tone]} role={feedback.tone === "error" ? "alert" : "status"}>
            <span>{feedback.text}</span>
            <button type="button" className="action-feedback-close" aria-label="Fermer le message" onClick={() => setFeedback(null)}>×</button>
          </p>
        )}
      </div>
    </ActionFeedbackContext.Provider>
  );
}

export function useActionFeedback(): ActionFeedback {
  const context = useContext(ActionFeedbackContext);
  if (!context) throw new Error("useActionFeedback doit être utilisé dans StaffShell (ActionFeedbackProvider).");
  return context;
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
          <button className="btn s staff-logout" onClick={logout}>Déconnexion</button>
        </div>
        {tabs && !user?.must_change_password && (
          <nav className="wrap staff-tabs" aria-label="Sections">
            {tabs.map(([key, label]) => (
              <button key={key} className={current === key ? "on" : ""} aria-current={current === key ? "page" : undefined} onClick={() => onTab?.(key)}>
                {label}
              </button>
            ))}
          </nav>
        )}
      </header>
      <main className="wrap staff-main">
        {user?.must_change_password
          ? <ForcedPasswordChange onDone={() => window.location.reload()} />
          : <ActionFeedbackProvider>{children}</ActionFeedbackProvider>}
      </main>
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
          <button className="btn s staff-logout" onClick={logout}>Déconnexion</button>
        </div>
      </header>
      <main className="wrap staff-login">
        <section className="login-card text-center">
          <p className="eyebrow text-red-700">Accès refusé</p>
          <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Espace réservé à {area}</h1>
          <p className="mt-3 text-sm leading-6 text-slate-600">Votre compte est connecté, mais son rôle ne permet pas d’ouvrir cette interface.</p>
          <div className="mt-6 grid gap-3">
            {/* Session d'un autre compte (souvent le compte client) : on la ferme pour revenir à la connexion. */}
            <button type="button" className="primary-button" onClick={logout}>Se connecter avec un autre compte</button>
            <a className="secondary-button" href="/">Retour à l’espace client</a>
          </div>
        </section>
      </main>
    </div>
  );
}
