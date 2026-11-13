"use client";

import { useEffect, useRef } from "react";
import { clearTokens, getAccessToken, markSessionExpired, touchActivity } from "./api";
import { ACTIVITY_EVENTS, ACTIVITY_KEY, INACTIVITY_CHECK_MS, INACTIVITY_LIMIT_MS, SESSION_EXPIRED_EVENT, inactivityExpired, parseActivity } from "./session";

// Surveille la session d'un portail : activité de l'utilisateur, inactivité, fin de session signalée par la couche API.
// `onExpired` est appelé une fois par expiration ; le portail décide de l'affichage (boîte de reconnexion).
export function useSessionGuard(onExpired: () => void) {
  const callback = useRef(onExpired);
  callback.current = onExpired;

  useEffect(() => {
    const expire = () => callback.current();
    const activity = () => { if (getAccessToken()) touchActivity(); };
    const check = () => {
      if (!getAccessToken()) return;
      let last: number | null = null;
      try { last = parseActivity(window.localStorage.getItem(ACTIVITY_KEY)); } catch { last = null; }
      if (last === null) { touchActivity(); return; }
      if (inactivityExpired(last, Date.now(), INACTIVITY_LIMIT_MS)) markSessionExpired();
    };
    // Autre onglet déconnecté (jetons retirés) : cet onglet suit.
    const storage = (event: StorageEvent) => {
      if (event.key === "axis_access_token" && event.newValue === null && event.oldValue) { clearTokens(); expire(); }
    };
    if (getAccessToken()) touchActivity();
    ACTIVITY_EVENTS.forEach((name) => window.addEventListener(name, activity, { passive: true }));
    window.addEventListener(SESSION_EXPIRED_EVENT, expire);
    window.addEventListener("storage", storage);
    const timer = window.setInterval(check, INACTIVITY_CHECK_MS);
    check();
    return () => {
      ACTIVITY_EVENTS.forEach((name) => window.removeEventListener(name, activity));
      window.removeEventListener(SESSION_EXPIRED_EVENT, expire);
      window.removeEventListener("storage", storage);
      window.clearInterval(timer);
    };
  }, []);
}
