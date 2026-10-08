import Link from "next/link";

export function Brand({ light = false }: { light?: boolean }) {
  return (
    <Link href="/" className={`font-bold tracking-tight ${light ? "text-white" : "text-axis-900"}`}>
      <span className="text-xl">Axis</span>
      <span className={light ? "text-axis-300" : "text-axis-600"}>Transport</span>
    </Link>
  );
}

