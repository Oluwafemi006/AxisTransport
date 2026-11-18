// Tests des règles de src/lib/pwa.ts (PWA par espace, paiement embarqué) et de la cohérence des manifestes.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/pwa.ts"), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-pwa-")), "pwa.mjs");
writeFileSync(compiled, outputText);
const { SPACES, embeddedPaymentAvailable, paymentDialogOutcome, legacyServiceWorkerScopes, shouldAutoVerify } = await import(pathToFileURL(compiled).href);

const fedapay = { transaction_id: "123456", payment_url: "https://exemple.test/paiement/TEST", simulated: false };

test("paiement dans la page : clé publique, transaction FedaPay numérique, page de repli", () => {
  assert.equal(embeddedPaymentAvailable("pk_TEST", fedapay), true);
  assert.equal(embeddedPaymentAvailable("", fedapay), false, "sans clé : redirection");
  assert.equal(embeddedPaymentAvailable("   ", fedapay), false);
  assert.equal(embeddedPaymentAvailable("pk_TEST", { ...fedapay, simulated: true }), false, "paiement simulé : jamais FedaPay");
  assert.equal(embeddedPaymentAvailable("pk_TEST", { ...fedapay, payment_url: null }), false);
  assert.equal(embeddedPaymentAvailable("pk_TEST", { ...fedapay, transaction_id: "SIM-TEST" }), false);
  assert.equal(embeddedPaymentAvailable("pk_TEST", null), false);
});

test("fin du dialogue : seule la constante « terminé » du script vaut un paiement à vérifier", () => {
  assert.equal(paymentDialogOutcome(1, 1), "completed");
  assert.equal(paymentDialogOutcome(2, 1), "dismissed");
  assert.equal(paymentDialogOutcome(undefined, 1), "dismissed");
  assert.equal(paymentDialogOutcome(1, undefined), "dismissed", "constante inconnue : rien n'est supposé");
});

test("anciens service workers : seule la portée « / » du site est retirée", () => {
  const origin = "https://exemple.test";
  const scopes = [`${origin}/`, `${origin}/controleur`, "https://autre.test/"];
  assert.deepEqual(legacyServiceWorkerScopes(scopes, origin), [`${origin}/`]);
  assert.deepEqual(legacyServiceWorkerScopes(scopes, `${origin}/`), [`${origin}/`]);
  assert.deepEqual(legacyServiceWorkerScopes([`${origin}/controleur`], origin), []);
});

test("vérification automatique : la première fois, puis au plus toutes les 5 s", () => {
  assert.equal(shouldAutoVerify(null, 1000), true);
  assert.equal(shouldAutoVerify(1000, 3000), false);
  assert.equal(shouldAutoVerify(1000, 6000), true);
});

test("manifestes : un par espace, portée = démarrage = identifiant, mêmes icônes", () => {
  const expected = { client: "/", admin: "/admin", guichet: "/guichet", controleur: "/controleur" };
  for (const [space, scope] of Object.entries(expected)) {
    assert.equal(SPACES[space].scope, scope);
    const file = path.join(here, "../public", SPACES[space].manifest.replace(/^\//, ""));
    const manifest = JSON.parse(readFileSync(file, "utf8"));
    assert.equal(manifest.scope, scope, space);
    assert.equal(manifest.start_url, scope, space);
    assert.equal(manifest.id, scope, space);
    assert.equal(manifest.display, "standalone", space);
    assert.equal(manifest.lang, "fr", space);
    assert.deepEqual(manifest.icons.map((icon) => icon.src), ["/icon-192.png", "/icon-512.png"], space);
  }
});

test("service worker : portée contrôleur, aucun repli vers « / » ni vers une autre page", () => {
  const sw = readFileSync(path.join(here, "../public/sw.js"), "utf8");
  assert.match(sw, /SCOPE_PATH = "\/controleur"/);
  assert.match(sw, /request\.mode === "navigate" && inControllerSpace/);
  assert.doesNotMatch(sw, /SHELL = \[[^\]]*"\/"[,\]]/, "la page d'accueil n'est plus mise en cache");
});
