// Tests de src/lib/ticket-print.ts, compilé ici comme portal-rules.ts ; `money` est remplacé pour éviter d'importer api.ts.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/ticket-print.ts"), "utf8").replace(
  'import { money } from "./api";',
  "const money = (amount) => `${amount} FCFA`;",
);
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-ticket-print-")), "ticket-print.mjs");
writeFileSync(compiled, outputText);
const { ticketFooter, ticketRows } = await import(pathToFileURL(compiled).href);

test("une mention vide de l'agence n'a aucune ligne", () => {
  const footer = ticketFooter({ agency: { legal_name: "  ", ifu: "", rccm: "TEST-RCCM", address: "", phones: "", email: "" }, conditions: "" });
  assert.deepEqual(footer, ["RCCM : TEST-RCCM"]);
});

test("sans information d'agence, le bas du billet est vide", () => {
  assert.deepEqual(ticketFooter(undefined), []);
});

test("une mention saisie dans l'admin apparaît", () => {
  const footer = ticketFooter({
    agency: { legal_name: "TEST Agence", ifu: "TEST-IFU", rccm: "TEST-RCCM", address: "TEST rue", phones: "TEST-TEL", email: "test@axis.test" },
    conditions: "TEST conditions",
  });
  assert.deepEqual(footer, [
    "Raison sociale : TEST Agence",
    "IFU : TEST-IFU · RCCM : TEST-RCCM",
    "Adresse : TEST rue",
    "Contacts : TEST-TEL · test@axis.test",
    "Conditions : TEST conditions",
  ]);
});

test("le billet ne contient ni TVA ni TTC", () => {
  const rows = ticketRows(
    { reference: "TEST-1", origin: "Parakou", destination: "Savè", boarding_at: null, departure_at: null, arrival_at: null, seat_label: "1A", passenger_name: "TEST", amount: 4500, currency: "XOF" },
    (iso) => iso,
  );
  assert.doesNotMatch(rows.flat().join(" "), /TVA|TTC/);
});
