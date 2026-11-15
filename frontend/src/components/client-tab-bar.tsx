"use client";

import type { ComponentType } from "react";
import { CarIcon, HomeIcon, PackageIcon, TicketIcon, UserIcon } from "./icons";

export type ClientTab = "accueil" | "billets" | "colis" | "location" | "profil";

// Mêmes onglets et même ordre que l'application mobile (mobile-flutter/lib/core/widgets/axis_bottom_nav.dart, clientItems).
export const CLIENT_TABS: Array<{ key: ClientTab; label: string; Icon: ComponentType<{ size?: number }> }> = [
  { key: "accueil", label: "Accueil", Icon: HomeIcon },
  { key: "billets", label: "Billets", Icon: TicketIcon },
  { key: "location", label: "Location", Icon: CarIcon },
  { key: "colis", label: "Colis", Icon: PackageIcon },
  { key: "profil", label: "Profil", Icon: UserIcon },
];

// Barre d'onglets fixée en bas de l'écran, affichée seulement sur téléphone et petite tablette
// (même seuil que le menu du haut, masqué sous 900 px : globals.css, .menu).
export function ClientTabBar({ current, onSelect }: { current: ClientTab; onSelect: (tab: ClientTab) => void }) {
  return (
    <nav className="tabbar" aria-label="Navigation principale">
      {CLIENT_TABS.map(({ key, label, Icon }) => (
        <button
          key={key}
          type="button"
          className={current === key ? "on" : ""}
          aria-current={current === key ? "page" : undefined}
          onClick={() => { onSelect(key); window.scrollTo({ top: 0 }); }}
        >
          <Icon size={24} />
          <span>{label}</span>
        </button>
      ))}
    </nav>
  );
}
