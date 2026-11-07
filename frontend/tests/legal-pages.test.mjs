// Pages publiques /privacy et /suppression-compte (src/lib/legal-pages.ts), compilées ici avec le TypeScript du projet.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/legal-pages.ts"), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-legal-")), "legal-pages.mjs");
writeFileSync(compiled, outputText);
const { privacyPage, accountDeletionPage, readPrivacyContact, EMPTY_CONTACT, loadPrivacyContact } = await import(pathToFileURL(compiled).href);

const contact = { legal_name: "TEST agence", email: "contact.test@exemple.test", contact_phone: "TEST 0100000000", contact_whatsapp: "" };

test("aucun script, page en français, liens entre les deux pages", () => {
  for (const html of [privacyPage(contact), accountDeletionPage(contact)]) {
    assert.doesNotMatch(html, /<script/i);
    assert.match(html, /<html lang="fr">/);
    assert.match(html, /href="\/privacy"/);
    assert.match(html, /href="\/suppression-compte"/);
  }
});

test("coordonnées saisies dans /admin affichées ; WhatsApp vide masqué", () => {
  const html = privacyPage(contact);
  assert.match(html, /TEST agence/);
  assert.match(html, /E-mail : contact\.test@exemple\.test/);
  assert.match(html, /Téléphone : TEST 0100000000/);
  assert.doesNotMatch(html, /WhatsApp :/);
});

test("sans coordonnées : « À renseigner », jamais de valeur inventée", () => {
  const html = privacyPage(EMPTY_CONTACT);
  assert.match(html, /Coordonnées : À renseigner\./);
  assert.match(html, /Axis Transport/);
});

test("les points ouverts sont marqués « À valider »", () => {
  const privacy = privacyPage(contact);
  for (const point of ["personne responsable", "nom du service", "hébergeur", "durée de conservation"]) assert.match(privacy, new RegExp(`À valider : [^<]*${point}`));
  assert.match(accountDeletionPage(contact), /<span class="c">À CONFIRMER<\/span>/);
});

test("ni FedaPay au client autrement que comme prestataire, ni numéro d'enregistrement, ni facture", () => {
  const html = privacyPage(contact) + accountDeletionPage(contact);
  assert.doesNotMatch(html, /IFU de l’agence|RCCM|NIM|MeCeF|facture/i);
  assert.match(html, /jamais votre nom ni votre téléphone/);
});

test("texte saisi échappé : aucune balise injectée", () => {
  const html = privacyPage({ ...contact, legal_name: '<img src=x onerror="alert(1)">' });
  assert.doesNotMatch(html, /<img/);
  assert.match(html, /&lt;img/);
});

test("lecture des coordonnées : champs absents ou non texte = vides", () => {
  assert.deepEqual(readPrivacyContact(null), EMPTY_CONTACT);
  assert.deepEqual(readPrivacyContact({ email: 42, legal_name: " TEST " }), { ...EMPTY_CONTACT, legal_name: "TEST" });
});

test("API injoignable ou adresse absente : la page s'affiche quand même", async () => {
  assert.deepEqual(await loadPrivacyContact(undefined), EMPTY_CONTACT);
  assert.deepEqual(await loadPrivacyContact("http://127.0.0.1:9/api/v1"), EMPTY_CONTACT);
});

test("/confidentialite redirige vers /privacy", () => {
  const config = readFileSync(path.join(here, "../next.config.ts"), "utf8");
  assert.match(config, /source: "\/confidentialite", destination: "\/privacy", permanent: true/);
});

test("suppression : procédure par l'application ou par e-mail, données supprimées et conservées", () => {
  const html = accountDeletionPage(contact);
  assert.match(html, /<strong>Axis Transport<\/strong>/);
  assert.match(html, /« Supprimer mon compte »/);
  assert.match(html, /par e-mail à <strong>contact\.test@exemple\.test<\/strong>/);
  assert.match(html, /<h2>Données supprimées<\/h2>/);
  assert.match(html, /<h2>Données conservées sous forme anonymisée<\/h2>/);
  assert.match(html, /Données anonymisées \(billets, paiements, colis, locations\) : <span class="c">À CONFIRMER<\/span>/);
});

test("suppression : sans e-mail saisi, aucune adresse inventée", () => {
  const html = accountDeletionPage(EMPTY_CONTACT);
  assert.match(html, /adresse de contact de l’agence \(<span class="c">À CONFIRMER<\/span> : adresse non encore saisie\)/);
  assert.match(html, /<strong>Axis Transport<\/strong>/);
});

test("suppression : cas de refus et limite des notes d'historique annoncés", () => {
  const html = accountDeletionPage(contact);
  for (const words of ["billet payé pour un voyage qui n’est pas encore parti", "colis qui n’est pas encore retiré", "location demandée, confirmée ou en cours", "paiement Mobile Money encore en attente", "notes libres"]) {
    assert.ok(html.includes(words), words);
  }
});
