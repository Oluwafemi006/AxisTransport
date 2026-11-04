import type { Metadata } from "next";
import { ParcelTicket } from "./parcel-ticket";

export const metadata: Metadata = { title: "Ticket colis", robots: { index: false } };

export default async function ParcelTicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ParcelTicket id={id} />;
}
