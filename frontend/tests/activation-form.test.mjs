// Test de rendu basique du formulaire d'activation du personnel.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/components/activation-form.tsx"), "utf8");
const { outputText } = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.ESNext,
    target: ts.ScriptTarget.ES2020,
    jsx: ts.JsxEmit.ReactJSX,
  },
});
const compiled = path.join(here, ".activation-form.test.tmp.mjs");
writeFileSync(compiled, outputText);

let ActivationForm;
try {
  const mod = await import(pathToFileURL(compiled).href);
  ActivationForm = mod.ActivationForm;
} finally {
  try { unlinkSync(compiled); } catch {}
}

test("rendu du formulaire d'activation : titre, champs mot de passe et bouton", () => {
  const html = renderToStaticMarkup(
    React.createElement(ActivationForm, {
      email: "agent.test@axis.bj",
      group: "Guichetier",
      roleLabel: "Guichetier",
      password: "",
      confirmPassword: "",
      submitting: false,
      submitError: null,
    })
  );

  assert.ok(html.includes("Définissez votre mot de passe pour activer votre compte AXIS"));
  assert.ok(html.includes("agent.test@axis.bj"));
  assert.ok(html.includes("Guichetier"));
  assert.ok(html.includes('id="password"'));
  assert.ok(html.includes('id="confirmPassword"'));
  assert.ok(html.includes("Activer mon compte"));
});

test("rendu du formulaire d'activation : affichage d'une erreur de saisie", () => {
  const html = renderToStaticMarkup(
    React.createElement(ActivationForm, {
      submitError: "Les deux mots de passe ne correspondent pas.",
    })
  );

  assert.ok(html.includes("Les deux mots de passe ne correspondent pas."));
  assert.ok(html.includes('role="alert"'));
});

test("rendu du formulaire d'activation : état de soumission désactivé", () => {
  const html = renderToStaticMarkup(
    React.createElement(ActivationForm, {
      submitting: true,
    })
  );

  assert.ok(html.includes("Activation en cours…"));
  assert.ok(html.includes("disabled"));
});
