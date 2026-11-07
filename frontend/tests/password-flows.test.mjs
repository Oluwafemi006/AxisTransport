// Parcours du mot de passe sur le site : vérifiés dans le code source (aucune dépendance de plus).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (file) => readFileSync(path.join(here, "../src", file), "utf8");

test("admin : un client reçoit un lien, jamais un mot de passe saisi par l'admin", () => {
  const admin = read("components/admin-portal.tsx");
  const row = admin.slice(admin.indexOf('{user.role === "CLIENT"'), admin.indexOf(">Mot de passe provisoire</button>"));
  assert.match(row, /\? <button[\s\S]*sendResetLink\(user\)[\s\S]*>Lien de réinitialisation<\/button>\s*: <button[\s\S]*setResetTarget\(user\)/);
  assert.match(admin, /\/users\/\$\{user\.id\}\/reset-link\//);
  assert.match(admin, />Copier le lien<\/button>/);
});

test("mot de passe oublié : l'e-mail seulement, plus aucun code", () => {
  const login = read("components/login-card.tsx");
  const forgot = login.slice(login.indexOf("function ForgotPassword"), login.indexOf("export function LoginCard"));
  assert.match(forgot, /Recevoir un lien/);
  assert.doesNotMatch(forgot, /code/i);
});

test("page /nouveau-mot-de-passe : vérifie le lien puis l'utilise", () => {
  const page = read("app/nouveau-mot-de-passe/page.tsx");
  assert.match(page, /checkPasswordResetLink\(value\)/);
  assert.match(page, /submitPasswordResetLink\(token, password\)/);
  const api = read("lib/api.ts");
  assert.match(api, /\/auth\/password-reset\/link\//);
  assert.doesNotMatch(api, /password-reset\/confirm/);
});

test("mot de passe provisoire : seul l'écran de changement s'affiche, partout", () => {
  const ui = read("components/ui.tsx");
  assert.match(ui, /user\?\.must_change_password\s*\?\s*<ForcedPasswordChange/);
  for (const file of ["components/controller-portal.tsx", "components/counter-portal.tsx", "components/client-portal.tsx"]) {
    assert.match(read(file), /if \(me\.must_change_password\) \{ setUser\(me\); return; \}/, file);
  }
  assert.match(read("components/client-portal.tsx"), /if \(user\?\.must_change_password\) return <ForcedPasswordChange/);
});
