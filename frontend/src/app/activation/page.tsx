import { Suspense } from "react";
import type { Metadata } from "next";
import { ActivationContent } from "./activation-content";

export const metadata: Metadata = {
  title: "Activation de compte",
  description: "Définissez votre mot de passe pour activer votre compte AXIS Transport.",
};

export default function ActivationPage() {
  return (
    <main className="min-h-screen bg-slate-100 flex flex-col justify-center py-12 px-4 sm:px-6 lg:px-8">
      <Suspense
        fallback={
          <div className="login-card mx-auto max-w-md my-8 text-center py-12">
            <p className="text-slate-600 font-medium">Chargement de la page d’activation…</p>
          </div>
        }
      >
        <ActivationContent />
      </Suspense>
    </main>
  );
}
