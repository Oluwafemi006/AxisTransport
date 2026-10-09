import Link from "next/link";

// Logo officiel Axis Transport. Sur fond sombre (light), l'emblème seul avec le nom en blanc.
export function Brand({ light = false }: { light?: boolean }) {
  if (light) {
    return (
      <Link href="/" className="logo" style={{ color: "#fff" }}>
        <img src="/images/axis-emblem.png" alt="" width={192} height={192} />AXIS Transport
      </Link>
    );
  }
  return (
    <Link href="/" className="logo">
      <img src="/images/axis-logo.png" alt="AXIS Transport" width={570} height={176} />
    </Link>
  );
}
