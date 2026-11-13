// Tests des règles de session de src/lib/session.ts (renouvellement, inactivité), sans navigateur.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/session.ts"), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-session-")), "session.mjs");
writeFileSync(compiled, outputText);
const { INACTIVITY_LIMIT_MS, SESSION_EXPIRED_MESSAGE, inactivityExpired, shouldRefresh, refreshedTokens, parseActivity } = await import(pathToFileURL(compiled).href);

test("inactivité : 30 minutes par défaut, jamais sans horodatage connu", () => {
  assert.equal(INACTIVITY_LIMIT_MS, 30 * 60 * 1000);
  const start = 1_000_000;
  assert.equal(inactivityExpired(null, start + INACTIVITY_LIMIT_MS * 2), false);
  assert.equal(inactivityExpired(start, start + INACTIVITY_LIMIT_MS - 1), false);
  assert.equal(inactivityExpired(start, start + INACTIVITY_LIMIT_MS), true);
  assert.equal(inactivityExpired(start, start + 60_000, 60_000), true, "limite paramétrable");
});

test("renouvellement : 401 d'une requête authentifiée, un jeton de renouvellement, une seule fois", () => {
  assert.equal(shouldRefresh(401, true, true, false), true);
  assert.equal(shouldRefresh(401, true, true, true), false, "pas de seconde tentative");
  assert.equal(shouldRefresh(401, true, false, false), false, "sans jeton de renouvellement");
  assert.equal(shouldRefresh(401, false, true, false), false, "requête publique");
  assert.equal(shouldRefresh(403, true, true, false), false);
  assert.equal(shouldRefresh(500, true, true, false), false);
});

test("réponse du renouvellement : accès obligatoire, nouveau jeton de renouvellement si fourni (rotation)", () => {
  assert.deepEqual(refreshedTokens({ access: "a-TEST", refresh: "r-TEST" }), { access: "a-TEST", refresh: "r-TEST" });
  assert.deepEqual(refreshedTokens({ access: "a-TEST" }), { access: "a-TEST", refresh: null });
  assert.equal(refreshedTokens({ refresh: "r-TEST" }), null);
  assert.equal(refreshedTokens({ access: "" }), null);
  assert.equal(refreshedTokens(null), null);
  assert.equal(refreshedTokens("texte"), null);
});

test("horodatage d'activité conservé : tolérant aux valeurs absentes ou corrompues", () => {
  assert.equal(parseActivity(null), null);
  assert.equal(parseActivity(""), null);
  assert.equal(parseActivity("abc"), null);
  assert.equal(parseActivity("-5"), null);
  assert.equal(parseActivity("1700000000000"), 1700000000000);
});

test("message unique de session expirée, en français", () => {
  assert.match(SESSION_EXPIRED_MESSAGE, /^Session expirée/);
});
