"use client";

import { useSearchParams } from "next/navigation";
import { ActivationCard } from "@/components/activation-card";

export function ActivationContent() {
  const searchParams = useSearchParams();
  const token = searchParams.get("token");

  return <ActivationCard token={token} />;
}
