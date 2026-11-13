import type { Metadata } from "next";
import { AdminPortal } from "@/components/admin-portal";

// Installable séparément : manifeste et portée propres à cet espace (voir src/lib/pwa.ts).
export const metadata: Metadata = { title: "Administration", manifest: "/manifest-admin.webmanifest", appleWebApp: { capable: true, title: "Axis Admin", statusBarStyle: "default" } };

export default function AdminPage() {
  return <AdminPortal />;
}

