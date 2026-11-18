import type { Metadata } from "next";
import { CounterPortal } from "@/components/counter-portal";

// Installable séparément : manifeste et portée propres à cet espace (voir src/lib/pwa.ts).
export const metadata: Metadata = { title: "Guichet", manifest: "/manifest-guichet.webmanifest", appleWebApp: { capable: true, title: "Axis Guichet", statusBarStyle: "default" } };

export default function CounterPage() {
  return <CounterPortal />;
}
