import Link from "next/link";

// Logo officiel Axis Transport. Sur fond sombre (light), l'emblème seul avec le nom en blanc.
// `href` : accueil de l'espace en cours (portails du personnel) ; le site client par défaut.
export function Brand({ light = false, href = "/" }: { light?: boolean; href?: string }) {
  if (light) {
    return (
      <Link href={href} className="logo" style={{ color: "#fff" }}>
        <img src="/images/axis-emblem.png" alt="" width={192} height={192} />AXIS Transport
      </Link>
    );
  }
  return (
    <Link href={href} className="logo">
      <img src="/images/axis-logo.png" alt="AXIS Transport" width={570} height={176} />
    </Link>
  );
}
