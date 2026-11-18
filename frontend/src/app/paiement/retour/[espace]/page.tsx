import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { StaffPaymentReturn } from "@/components/staff-payment-return";
import { STAFF_SPACES, isStaffSpace } from "@/lib/staff-sale";

export const metadata: Metadata = { title: "Retour du paiement" };

// Seules les trois pages de la liste fixe existent : toute autre valeur répond 404 (pas de redirection ouverte).
export const dynamicParams = false;

export function generateStaticParams() {
  return STAFF_SPACES.map((espace) => ({ espace }));
}

export default async function StaffPaymentReturnPage({ params }: { params: Promise<{ espace: string }> }) {
  const { espace } = await params;
  if (!isStaffSpace(espace)) notFound();
  return <StaffPaymentReturn space={espace} />;
}
