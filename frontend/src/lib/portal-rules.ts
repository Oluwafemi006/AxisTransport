// Règles d'affichage du site et du portail, sans dépendance : testées par `npm test` (tests/portal-rules.test.mjs).

// Durée de blocage d'un siège (« ticket_hold_minutes ») : sans elle, aucune réservation n'est possible.
export function holdMinutesConfigured(settings: Array<{ key: string; value: unknown }>): boolean {
  const item = settings.find((setting) => setting.key === "ticket_hold_minutes");
  if (!item || item.value === null || item.value === "") return false;
  const minutes = Number(item.value);
  return Number.isInteger(minutes) && minutes > 0;
}

// Libellé d'un départ dans la vente au guichet : parcours, date et heure, prix TTC (ou son absence).
export function counterTripLabel(routeLabel: string, departure: string, price: string | null): string {
  return `${routeLabel} · ${departure} · ${price ?? "sans prix (non vendable)"}`;
}

// Texte d'erreur d'une action du portail, toujours en français et sans texte technique.
// `reason` : erreur levée par apiFetch (avec `status`) ou par le navigateur (sans `status`).
export function actionErrorText(reason: unknown, failed: string): string {
  const error = (reason ?? {}) as { status?: unknown; message?: unknown; name?: unknown };
  const status = typeof error.status === "number" ? error.status : null;
  if (status === null) {
    // Pas de réponse du serveur (réseau coupé, serveur arrêté) : le navigateur lève une TypeError.
    if (error.name === "TypeError") return `${failed} Le serveur ne répond pas : vérifiez la connexion et réessayez.`;
    return `${failed} Vérifiez les valeurs saisies et réessayez.`;
  }
  if (status === 401) return `${failed} Votre session a expiré : reconnectez-vous, puis recommencez.`;
  if (status === 403) return `${failed} Votre compte n’a pas le droit de faire cette action.`;
  if (status >= 500) return `${failed} Le serveur a rencontré un problème : réessayez dans quelques minutes.`;
  // Erreur métier (400, 404, 409…) : le serveur répond en français ; son message explique la cause.
  const message = typeof error.message === "string" ? error.message.trim() : "";
  if (!message || message === "Une erreur est survenue.") return `${failed} Vérifiez les valeurs saisies et réessayez.`;
  return `${failed} ${message}`;
}

