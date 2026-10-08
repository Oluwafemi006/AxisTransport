import type { Metadata } from "next";
import { ControllerPortal } from "@/components/controller-portal";

export const metadata: Metadata = { title: "Contrôle des billets" };

export default function ControllerPage() {
  return <ControllerPortal />;
}
