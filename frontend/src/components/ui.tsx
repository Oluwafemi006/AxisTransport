import { ReactNode } from "react";

export function StatusBadge({ children, tone = "blue" }: { children: ReactNode; tone?: "blue" | "green" | "amber" | "red" }) {
  const styles = {
    blue: "bg-axis-100 text-axis-800",
    green: "bg-emerald-100 text-emerald-800",
    amber: "bg-amber-100 text-amber-800",
    red: "bg-red-100 text-red-800",
  };
  return <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${styles[tone]}`}>{children}</span>;
}

export function EmptyState({ title, text }: { title: string; text: string }) {
  return (
    <div className="rounded-2xl border border-dashed border-axis-200 bg-axis-50/70 px-5 py-8 text-center">
      <p className="font-semibold text-axis-900">{title}</p>
      <p className="mx-auto mt-1 max-w-md text-sm text-slate-500">{text}</p>
    </div>
  );
}

export function SectionHeading({ eyebrow, title, action }: { eyebrow?: string; title: string; action?: ReactNode }) {
  return (
    <div className="mb-4 flex items-end justify-between gap-4">
      <div>{eyebrow && <p className="eyebrow">{eyebrow}</p>}<h2 className="text-xl font-bold text-axis-950">{title}</h2></div>
      {action}
    </div>
  );
}

export function AccessDenied({ area }: { area: string }) {
  return (
    <main className="grid min-h-screen place-items-center bg-axis-50 px-4">
      <section className="w-full max-w-lg rounded-3xl border border-red-100 bg-white p-8 text-center shadow-card">
        <p className="eyebrow text-red-700">Accès refusé</p>
        <h1 className="mt-2 text-2xl font-bold text-axis-950">Espace réservé à {area}</h1>
        <p className="mt-3 text-sm leading-6 text-slate-600">Votre compte est connecté, mais son rôle ne permet pas d’ouvrir cette interface.</p>
        <a className="primary-button mt-6 inline-flex" href="/">Retour à l’espace client</a>
      </section>
    </main>
  );
}
