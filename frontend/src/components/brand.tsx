import Link from "next/link";

// Logo du site client (pastille « A » + nom), réutilisé tel quel dans les portails équipe.
export function Brand({ light = false }: { light?: boolean }) {
  return (
    <Link href="/" className="logo" style={light ? { color: "#fff" } : undefined}>
      <i style={light ? { background: "#fff", color: "var(--navy)" } : undefined}>A</i>AXIS Transport
    </Link>
  );
}
