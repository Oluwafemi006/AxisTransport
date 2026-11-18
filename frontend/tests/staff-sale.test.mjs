// Vente Mobile Money du personnel : liste fixe d'espaces, états de la page de retour, accueil selon l'espace.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/staff-sale.ts"), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-staff-sale-")), "staff-sale.mjs");
writeFileSync(compiled, outputText);
const sale = await import(pathToFileURL(compiled).href);

test("liste fixe d'espaces, identique à celle du serveur", () => {
  assert.deepEqual([...sale.STAFF_SPACES], ["guichet", "controleur", "admin"]);
  const server = readFileSync(path.join(here, "../../backend/apps/core/payments.py"), "utf8");
  assert.match(server, /STAFF_RETURN_SPACES = \("guichet", "controleur", "admin"\)/);
  for (const value of ["https://pirate.exemple.test", "../admin", "GUICHET", "client", "", null, 3]) {
    assert.equal(sale.isStaffSpace(value), false, String(value));
  }
});

test("accueil selon l'espace d'origine", () => {
  assert.equal(sale.staffSpaceHomePath("guichet"), "/guichet");
  assert.equal(sale.staffSpaceHomePath("controleur"), "/controleur");
  assert.equal(sale.staffSpaceHomePath("admin"), "/admin");
});

test("page de retour : les quatre états, décidés par le statut de la vente sur le serveur", () => {
  assert.equal(sale.staffReturnState("CONFIRMED", null), "paye");
  assert.equal(sale.staffReturnState("CONFIRMED", "declined"), "paye", "le serveur prime sur l'adresse");
  assert.equal(sale.staffReturnState("HELD", "approved"), "attente", "FedaPay dit « approuvé » : on attend la confirmation du serveur");
  assert.equal(sale.staffReturnState("HELD", null), "attente");
  assert.equal(sale.staffReturnState(null, null), "attente");
  assert.equal(sale.staffReturnState("HELD", "declined"), "echoue");
  assert.equal(sale.staffReturnState("HELD", "canceled"), "echoue");
  assert.equal(sale.staffReturnState("EXPIRED", null), "expire");
  assert.equal(sale.staffReturnState("CANCELLED", "approved"), "expire");
  for (const state of ["attente", "paye", "echoue", "expire"]) {
    assert.ok(sale.RETURN_MESSAGES[state].title && sale.RETURN_MESSAGES[state].text, state);
  }
  assert.equal(sale.isFinalState("paye"), true);
  assert.equal(sale.isFinalState("expire"), true);
  assert.equal(sale.isFinalState("attente"), false);
});

test("lien vers l'application : seulement pour un client sur Android", () => {
  const android = "Mozilla/5.0 (Linux; Android 14; TECNO KM5) Chrome/131 Mobile";
  const iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Safari/604.1";
  const pc = "Mozilla/5.0 (X11; Linux x86_64) Chrome/131";
  assert.equal(sale.showAndroidAppLink(android, false), true);
  assert.equal(sale.showAndroidAppLink(android, true), false, "jamais pour le personnel");
  assert.equal(sale.showAndroidAppLink(iphone, false), false);
  assert.equal(sale.showAndroidAppLink(pc, false), false);
});

test("vente en attente gardée dans le navigateur : rejetée si l'espace n'est pas dans la liste", () => {
  const ok = { bookingId: 12, paymentMethod: 3, transactionId: "7001", paymentUrl: "https://paiement.exemple.test/TEST", space: "guichet", savedAt: 1 };
  assert.deepEqual(sale.parsePendingSale(JSON.stringify(ok)), ok);
  assert.equal(sale.parsePendingSale(JSON.stringify({ ...ok, space: "https://pirate.exemple.test" })), null);
  assert.equal(sale.parsePendingSale("pas du json"), null);
  assert.deepEqual(sale.parseSaleResult(JSON.stringify({ bookingId: 12, state: "paye" })), { bookingId: 12, state: "paye", reference: null, at: 0 });
  assert.equal(sale.parseSaleResult(JSON.stringify({ bookingId: 12, state: "autre" })), null);
});

test("seules trois pages de retour du personnel existent", () => {
  const page = readFileSync(path.join(here, "../src/app/paiement/retour/[espace]/page.tsx"), "utf8");
  assert.match(page, /dynamicParams = false/);
  assert.match(page, /STAFF_SPACES\.map/);
});

test("page de retour rechargée : le dernier résultat final récent est réaffiché", () => {
  const now = 10_000_000;
  const paid = { bookingId: 41, state: "paye", reference: "AX-TEST-0001", at: now - 60_000 };
  assert.deepEqual(sale.recentFinalResult(paid, now), paid);
  assert.equal(sale.recentFinalResult({ ...paid, at: now - 31 * 60_000 }, now), null, "trop ancien");
  assert.equal(sale.recentFinalResult({ ...paid, state: "attente" }, now), null, "pas un résultat final");
  assert.equal(sale.recentFinalResult(null, now), null);
  assert.deepEqual(sale.parseSaleResult(JSON.stringify(paid)), paid);
});
