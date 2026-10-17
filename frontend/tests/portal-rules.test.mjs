// Tests des règles de src/lib/portal-rules.ts, sans dépendance de plus :
// le fichier est compilé ici avec le TypeScript du projet, puis importé.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/portal-rules.ts"), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-portal-rules-")), "portal-rules.mjs");
writeFileSync(compiled, outputText);
const { holdMinutesConfigured, counterTripLabel, actionErrorText } = await import(pathToFileURL(compiled).href);

test("durée de blocage : absente, vide, nulle ou invalide = non configurée", () => {
  assert.equal(holdMinutesConfigured([]), false);
  for (const value of [null, "", 0, -5, "abc", 1.5]) {
    assert.equal(holdMinutesConfigured([{ key: "ticket_hold_minutes", value }]), false, String(value));
  }
  assert.equal(holdMinutesConfigured([{ key: "ticket_hold_minutes", value: 15 }]), true);
  assert.equal(holdMinutesConfigured([{ key: "ticket_hold_minutes", value: "10" }]), true);
});

test("le départ au guichet affiche parcours, date et prix, ou son absence", () => {
  assert.equal(counterTripLabel("Parakou → Cotonou", "18 oct. 2026, 07:00", "7 500 FCFA"), "Parakou → Cotonou · 18 oct. 2026, 07:00 · 7 500 FCFA");
  assert.equal(counterTripLabel("Parakou → Cotonou", "18 oct. 2026, 07:00", null), "Parakou → Cotonou · 18 oct. 2026, 07:00 · sans prix (non vendable)");
});

test("erreur d'action : toujours en français, sans texte technique, jamais comme un succès", () => {
  const failed = "La règle n’a pas été enregistrée.";
  const network = Object.assign(new TypeError("Failed to fetch"), {});
  assert.equal(actionErrorText(network, failed), `${failed} Le serveur ne répond pas : vérifiez la connexion et réessayez.`);
  assert.equal(actionErrorText({ status: 401, message: "Given token not valid for any token type" }, failed), `${failed} Votre session a expiré : reconnectez-vous, puis recommencez.`);
  assert.equal(actionErrorText({ status: 403, message: "You do not have permission" }, failed), `${failed} Votre compte n’a pas le droit de faire cette action.`);
  assert.equal(actionErrorText({ status: 502, message: "Bad Gateway" }, failed), `${failed} Le serveur a rencontré un problème : réessayez dans quelques minutes.`);
  assert.equal(actionErrorText({ status: 400, message: "Ce champ est obligatoire." }, failed), `${failed} Ce champ est obligatoire.`);
  assert.equal(actionErrorText({ status: 400, message: "Une erreur est survenue." }, failed), `${failed} Vérifiez les valeurs saisies et réessayez.`);
  assert.equal(actionErrorText(null, failed), `${failed} Vérifiez les valeurs saisies et réessayez.`);
  assert.equal(actionErrorText(new SyntaxError("Unexpected token } in JSON"), failed), `${failed} Vérifiez les valeurs saisies et réessayez.`);
  for (const reason of [network, { status: 401 }, { status: 500 }, { status: 400, message: "x" }]) {
    const text = actionErrorText(reason, failed);
    assert.ok(text.startsWith(failed));
    assert.doesNotMatch(text, /Failed to fetch|token|permission|Gateway|JSON|enregistrée\.$/i);
  }
});

