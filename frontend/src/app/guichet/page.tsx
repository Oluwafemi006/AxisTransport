import type { Metadata } from "next";
import { CounterPortal } from "@/components/counter-portal";

export const metadata: Metadata = { title: "Guichet" };

export default function CounterPage() {
  return <CounterPortal />;
}
