import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Axis Transport", template: "%s · Axis Transport" },
  description: "Billetterie, colis et location de véhicules Axis Transport.",
  // Manifeste de l'espace client (portée « / »). Les espaces admin, guichet et contrôleur déclarent le leur.
  manifest: "/manifest.webmanifest",
  icons: { icon: "/icon-192.png", apple: "/icon-192.png" },
  // iPhone : Safari n'utilise pas le manifeste pour « Sur l'écran d'accueil » ; ces balises le remplacent.
  appleWebApp: { capable: true, title: "Axis", statusBarStyle: "default" },
};

export const viewport: Viewport = {
  themeColor: "#0b3c74",
  width: "device-width",
  initialScale: 1,
  // iPhone : expose la zone de sécurité du bas (barre d'accueil) à env(safe-area-inset-bottom).
  viewportFit: "cover",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}

