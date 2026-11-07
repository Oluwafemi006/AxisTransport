// Champ de mot de passe avec bouton afficher/masquer (src/components/password-input.tsx).
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/components/password-input.tsx"), "utf8");
const compiled = path.join(here, ".password-input.test.tmp.mjs");
writeFileSync(compiled, ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020, jsx: ts.JsxEmit.ReactJSX } }).outputText);
let PasswordInput;
try { ({ PasswordInput } = await import(pathToFileURL(compiled).href)); } finally { try { unlinkSync(compiled); } catch {} }

const render = (props) => renderToStaticMarkup(React.createElement(PasswordInput, { onChange() {}, value: "", ...props }));

test("masqué par défaut, bouton accessible qui ne soumet jamais le formulaire", () => {
  const html = render({ id: "password" });
  assert.match(html, /<input[^>]*type="password"/);
  assert.match(html, /<button[^>]*type="button"/);
  assert.match(html, /aria-label="Afficher le mot de passe"/);
  assert.match(html, /aria-pressed="false"/);
  assert.match(html, /aria-controls="password"/);
  // Cible tactile de 44 px au moins.
  assert.match(html, /width:44px;height:44px/);
});

test("id, name, autoComplete et autres attributs conservés sur le champ", () => {
  const html = render({ id: "confirmPassword", name: "confirmPassword", autoComplete: "new-password", required: true, minLength: 8, placeholder: "8 caractères minimum" });
  const input = html.match(/<input[^>]*>/)[0];
  for (const attribute of ['id="confirmPassword"', 'name="confirmPassword"', 'autoComplete="new-password"', "required", 'minLength="8"', 'placeholder="8 caractères minimum"']) {
    assert.ok(input.includes(attribute), attribute);
  }
  assert.match(input, /class="field"/);
});

test("aucun champ de mot de passe du site n'échappe au composant", () => {
  const root = path.join(here, "../src");
  const files = [];
  const walk = (dir) => { for (const name of readdirSync(dir)) { const full = path.join(dir, name); if (statSync(full).isDirectory()) walk(full); else if (full.endsWith(".tsx")) files.push(full); } };
  walk(root);
  for (const file of files) {
    if (file.endsWith("password-input.tsx")) continue;
    const text = readFileSync(file, "utf8");
    assert.doesNotMatch(text, /<input[^\n]*type="password"/, file);
    assert.doesNotMatch(text, /<input\s+id="(password|confirmPassword)"\s+name="[^"]+"\s+type="password"/, file);
  }
  const admin = readFileSync(path.join(root, "components/admin-portal.tsx"), "utf8");
  assert.match(admin, /type === "password"\s*\?\s*<PasswordInput[^\n]*autoComplete="new-password"/);
});

test("confirmation : chaque champ a son propre bouton", () => {
  for (const file of ["components/forced-password-change.tsx", "components/client-portal.tsx", "app/nouveau-mot-de-passe/page.tsx", "components/activation-form.tsx"]) {
    const text = readFileSync(path.join(here, "../src", file), "utf8");
    assert.ok((text.match(/<PasswordInput/g) || []).length >= 2, file);
  }
});
