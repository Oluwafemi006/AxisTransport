// La barre d'onglets du site reprend exactement les onglets client de l'application mobile, dans le même ordre.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const site = readFileSync(path.join(here, "../src/components/client-tab-bar.tsx"), "utf8");
const app = readFileSync(path.join(here, "../../mobile-flutter/lib/core/widgets/axis_bottom_nav.dart"), "utf8");
const css = readFileSync(path.join(here, "../src/app/globals.css"), "utf8");

test("mêmes onglets que l'application, même ordre", () => {
  const clientBlock = app.slice(app.indexOf("clientItems"), app.indexOf("controllerItems"));
  const appLabels = [...clientBlock.matchAll(/label: '([^']+)'/g)].map((m) => m[1]);
  const siteLabels = [...site.matchAll(/label: "([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(appLabels, ["Accueil", "Billets", "Location", "Colis", "Profil"]);
  assert.deepEqual(siteLabels, appLabels);
});

test("la barre apparaît au même seuil que celui qui masque le menu du haut", () => {
  assert.match(css, /@media\(max-width:900px\)\{\s*\.menu\{display:none\}/);
  assert.match(css, /\.tabbar \{ display: none; \}\s*@media \(max-width: 900px\)/);
});
