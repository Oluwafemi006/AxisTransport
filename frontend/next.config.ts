import type { NextConfig } from "next";

// L'adresse de l'API est obligatoire : sans elle, le site appellerait une adresse vide.
if (!process.env.NEXT_PUBLIC_API_URL) {
  throw new Error(
    "NEXT_PUBLIC_API_URL doit être définie (ex. https://api.exemple.test/api/v1). Voir DEPLOY.md.",
  );
}

const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "standalone",
};

export default nextConfig;
