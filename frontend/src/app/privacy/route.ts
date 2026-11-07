import { privacyPage, htmlResponse, loadPrivacyContact } from "@/lib/legal-pages";

// Page publique en HTML simple : aucun script, aucune connexion ; coordonnées relues dans /admin à chaque visite.
export const dynamic = "force-dynamic";

export async function GET() {
  return htmlResponse(privacyPage(await loadPrivacyContact(process.env.NEXT_PUBLIC_API_URL)));
}
