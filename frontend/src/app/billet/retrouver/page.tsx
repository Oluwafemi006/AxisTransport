import type { Metadata } from "next";
import { FindTicketForm } from "./find-ticket-form";

export const metadata: Metadata = {
  title: "Retrouver mon billet",
  description: "Retrouvez votre billet AXIS Transport avec sa référence et le téléphone utilisé à l’achat.",
  robots: { index: false },
};

export default function FindTicketPage() {
  return (
    <main className="min-h-screen bg-slate-100 flex flex-col justify-center px-4 py-12">
      <FindTicketForm />
    </main>
  );
}
