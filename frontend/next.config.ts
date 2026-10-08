import type { NextConfig } from "next";

// L'adresse de l'API est obligatoire : sans elle, le site appellerait une adresse vide.
if (!process.env.NEXT_PUBLIC_API_URL) {
  throw new Error(
    "NEXT_PUBLIC_API_URL doit être définie (ex. https://api.exemple.test/api/v1). Voir DEPLOY.md.",
  );
}

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Sortie « standalone » pour l'image Docker (server.js autonome). Sur Vercel (variable VERCEL),
  // la plateforme produit sa propre sortie : « standalone » y fait échouer la fin du build.
  ...(process.env.VERCEL ? {} : { output: "standalone" as const }),
};

export default nextConfig;
