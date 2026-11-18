// Flux de recherche du site : adresse de la page, jours, résumé, étapes, heure du Bénin, champs à 16 px.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
async function load(file) {
  const source = readFileSync(path.join(here, "../src/lib", file), "utf8");
  const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
  const out = path.join(mkdtempSync(path.join(tmpdir(), "axis-")), file.replace(".ts", ".mjs"));
  writeFileSync(out, outputText.replace(/from "\.\/(\w[\w-]*)"/g, 'from "./$1.mjs"'));
  return import(pathToFileURL(out).href);
}
const url = await load("search-url.ts");
const rules = await load("portal-rules.ts");

test("adresse : onglet et recherche relus tels quels, valeurs inconnues ignorées", () => {
  const location = url.readClientLocation("?onglet=billets&depart=1&arrivee=7&date=2026-11-19&passagers=2");
  assert.deepEqual(location, { tab: "billets", origin: "1", destination: "7", date: "2026-11-19", passengers: 2 });
  assert.equal(url.clientLocationSearch(location), "?onglet=billets&depart=1&arrivee=7&date=2026-11-19&passagers=2");
  assert.deepEqual(url.readClientLocation("?onglet=pirate&depart=x&date=19/11&passagers=99"), { tab: "accueil", origin: "", destination: "", date: "", passengers: 1 });
  assert.equal(url.clientLocationSearch({ tab: "accueil", origin: "", destination: "", date: "", passengers: 1 }), "");
  assert.equal(url.clientLocationSearch({ tab: "colis", origin: "", destination: "", date: "", passengers: 1 }), "?onglet=colis");
});

test("recherche complète : de quoi afficher le résumé au lieu de redemander le trajet", () => {
  assert.equal(url.hasCompleteSearch({ origin: "1", destination: "7", date: "2026-11-19" }), true);
  assert.equal(url.hasCompleteSearch({ origin: "1", destination: "1", date: "2026-11-19" }), false);
  assert.equal(url.hasCompleteSearch({ origin: "1", destination: "7", date: "" }), false);
});

test("jour précédent et suivant, passages de mois et d'année", () => {
  assert.equal(url.shiftDayKey("2026-11-19", 1), "2026-11-20");
  assert.equal(url.shiftDayKey("2026-11-30", 1), "2026-12-01");
  assert.equal(url.shiftDayKey("2027-01-01", -1), "2026-12-31");
});

test("résumé et étapes visibles", () => {
  assert.equal(url.searchSummary("Parakou", "Savè", "2026-11-19", 1), "Parakou → Savè · 19/11 · 1 passager");
  assert.equal(url.searchSummary("Parakou", "Savè", "2026-11-19", 3), "Parakou → Savè · 19/11 · 3 passagers");
  assert.deepEqual([...url.BOOKING_STEPS], ["Trajet", "Places et passagers", "Paiement", "Billet"]);
  assert.equal(url.bookingStep({ tripChosen: false, held: false, issued: false }), 1);
  assert.equal(url.bookingStep({ tripChosen: true, held: false, issued: false }), 2);
  assert.equal(url.bookingStep({ tripChosen: true, held: true, issued: false }), 3);
  assert.equal(url.bookingStep({ tripChosen: true, held: false, issued: true }), 4);
});

test("heures à l'heure du Bénin, quel que soit le fuseau de l'appareil", () => {
  // 07:00 UTC = 08:00 au Bénin (UTC+1).
  assert.match(rules.formatBeninDateTime("2026-11-19T07:00:00Z", { hour: "2-digit", minute: "2-digit" }), /08:00/);
  assert.equal(rules.formatDayKey("2026-11-19", { day: "2-digit", month: "2-digit" }), "19/11");
  const api = readFileSync(path.join(here, "../src/lib/api.ts"), "utf8");
  assert.match(api, /formatBeninDateTime\(value\)/);
  const ticket = readFileSync(path.join(here, "../src/app/t/[reference]/page.tsx"), "utf8");
  assert.match(ticket, /timeZone: "Africa\/Porto-Novo"/);
});

test("champs de saisie à 16 px sur téléphone (Safari iPhone ne zoome plus)", () => {
  const css = readFileSync(path.join(here, "../src/app/globals.css"), "utf8");
  assert.match(css, /@media \(max-width: 900px\) \{\s*input, select, textarea \{ font-size: 16px !important; \}/);
});

test("accueil : bouton d'inversion du départ et de l'arrivée", () => {
  const portal = readFileSync(path.join(here, "../src/components/client-portal.tsx"), "utf8");
  assert.match(portal, /setSearchOrigin\(searchDestination\); setSearchDestination\(searchOrigin\)/);
});
