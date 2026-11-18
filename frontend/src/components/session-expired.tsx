"use client";

import { SESSION_EXPIRED_MESSAGE } from "@/lib/session";
import { LoginCard } from "./login-card";

// Reconnexion par-dessus le portail resté affiché : les saisies en cours ne sont pas perdues.
export function SessionExpiredDialog({ title, onSuccess }: { title: string; onSuccess: () => void }) {
  return (
    <div role="dialog" aria-modal="true" aria-label="Session expirée" className="session-expired">
      <div className="session-expired-box">
        <p className="notice notice-error mb-3" role="alert">{SESSION_EXPIRED_MESSAGE}</p>
        <LoginCard title={title} onSuccess={onSuccess} />
      </div>
    </div>
  );
}
