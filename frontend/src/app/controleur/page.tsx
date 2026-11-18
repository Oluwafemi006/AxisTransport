import type { Metadata } from "next";
import { ControllerPortal } from "@/components/controller-portal";

// Installable séparément : manifeste et portée propres à cet espace (voir src/lib/pwa.ts).
export const metadata: Metadata = { title: "Contrôle des billets", manifest: "/manifest-controleur.webmanifest", appleWebApp: { capable: true, title: "Axis Contrôle", statusBarStyle: "default" } };

export default function ControllerPage() {
  return <ControllerPortal />;
}
