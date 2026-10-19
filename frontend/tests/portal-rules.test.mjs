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
const { placeChoices, searchError, holdMinutesConfigured, counterTripLabel, actionErrorText } = await import(pathToFileURL(compiled).href);

const places = [{ id: 1, name: "Cotonou" }, { id: 2, name: "Parakou" }];

test("aucune ville n'est retirée tant que l'autre liste est vide", () => {
  assert.deepEqual(placeChoices(places, "").map((place) => place.name), ["Cotonou", "Parakou"]);
});

test("la destination exclut le départ choisi, et inversement", () => {
  assert.deepEqual(placeChoices(places, "1").map((place) => place.name), ["Parakou"]);
  assert.deepEqual(placeChoices(places, "2").map((place) => place.name), ["Cotonou"]);
});

test("recherche refusée sans les deux villes, ou avec la même ville", () => {
  assert.equal(searchError("", ""), "Choisissez une ville de départ et une destination.");
  assert.equal(searchError("1", ""), "Choisissez une ville de départ et une destination.");
  assert.equal(searchError("", "2"), "Choisissez une ville de départ et une destination.");
  assert.equal(searchError("1", "1"), "La destination doit être différente de la ville de départ.");
  assert.equal(searchError("1", "2"), null);
});

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

test("lien d'appel : chiffres et « + » seulement, rien si vide ou invalide", async () => {
  const { phoneHref } = await import(pathToFileURL(compiled).href);
  assert.equal(phoneHref("+229 01 97 00 00 00"), "tel:+2290197000000");
  assert.equal(phoneHref("01 97 00 00 00"), "tel:0197000000");
  assert.equal(phoneHref("(+229) 97-00.00.00"), "tel:+22997000000");
  assert.equal(phoneHref(""), null);
  assert.equal(phoneHref("   "), null);
  assert.equal(phoneHref(null), null);
  assert.equal(phoneHref("À renseigner"), null);
  assert.equal(phoneHref("229+97"), null);
  assert.equal(phoneHref("+1234567890123456"), null);
});

test("lien WhatsApp : numéro international sans « + » ni espaces, rien sinon", async () => {
  const { whatsappHref } = await import(pathToFileURL(compiled).href);
  assert.equal(whatsappHref("+229 01 97 00 00 00"), "https://wa.me/2290197000000");
  assert.equal(whatsappHref("00229 97-00-00-00"), "https://wa.me/22997000000");
  assert.equal(whatsappHref(""), null);
  assert.equal(whatsappHref(null), null);
  assert.equal(whatsappHref("01 97 00 00 00"), null);
  assert.equal(whatsappHref("+229 abc"), null);
  assert.equal(whatsappHref("https://evil.example/+229"), null);
  assert.equal(whatsappHref("+1234567890123456"), null);
});

test("aujourd'hui = jour du Bénin (UTC+1), pas celui du navigateur ni UTC", async () => {
  const { beninDateKey } = await import(pathToFileURL(compiled).href);
  assert.equal(beninDateKey(new Date("2026-10-17T22:59:59Z")), "2026-10-17"); // 23 h 59 au Bénin
  assert.equal(beninDateKey(new Date("2026-10-17T23:00:00Z")), "2026-10-18"); // minuit au Bénin
  assert.equal(beninDateKey(new Date("2026-10-17T23:30:00Z")), "2026-10-18"); // départ à 00 h 30 : bon jour
  assert.equal(beninDateKey(new Date("2026-12-31T23:00:00Z")), "2027-01-01"); // changement d'année
});

test("date de recherche : vide, tapée à la main, passée ou invalide = message, sinon rien", async () => {
  const { searchDateError } = await import(pathToFileURL(compiled).href);
  const today = "2026-10-18";
  assert.equal(searchDateError("", today), "Choisissez une date de départ.");
  assert.equal(searchDateError("2026-10-17", today), "Choisissez une date à partir d’aujourd’hui.");
  assert.equal(searchDateError("2025-12-31", today), "Choisissez une date à partir d’aujourd’hui.");
  assert.equal(searchDateError("18/10/2026", today), "Date de départ invalide : choisissez-la dans le calendrier.");
  assert.equal(searchDateError("2026-13-45", today), "Date de départ invalide : choisissez-la dans le calendrier.");
  assert.equal(searchDateError("2026-10-18", today), null);
  assert.equal(searchDateError("2026-10-19", today), null);
});
