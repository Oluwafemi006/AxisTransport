// Icônes SVG du site (traits, couleur héritée) : remplacent les émojis, qui varient selon le téléphone et le navigateur.
import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement> & { size?: number; label?: string };

function Icon({ size = 22, label, children, ...rest }: IconProps) {
  return (
    <svg
      width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden={label ? undefined : true} role={label ? "img" : undefined}
      {...rest}
    >
      {label && <title>{label}</title>}
      {children}
    </svg>
  );
}

export function BusIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" />
      <path d="M4 11h16M8 18v2M16 18v2M2 8v4M22 8v4" />
      <circle cx="8" cy="15" r="1" fill="currentColor" stroke="none" /><circle cx="16" cy="15" r="1" fill="currentColor" stroke="none" />
    </Icon>
  );
}

export function TicketIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M3 9V7a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v2a3 3 0 0 0 0 6v2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-2a3 3 0 0 0 0-6z" />
      <path d="M9 6v12" strokeDasharray="2 2" />
    </Icon>
  );
}

export function PhoneIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <rect x="7" y="2.5" width="10" height="19" rx="2" />
      <path d="M11 18.5h2" />
    </Icon>
  );
}

export function PackageIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M12 3 4 7v10l8 4 8-4V7z" />
      <path d="M4 7l8 4 8-4M12 11v10M8 5l8 4" />
    </Icon>
  );
}

export function CarIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M5 11l1.6-4.2A2 2 0 0 1 8.5 5.5h7a2 2 0 0 1 1.9 1.3L19 11" />
      <path d="M3 13.5A1.5 1.5 0 0 1 4.5 12h15a1.5 1.5 0 0 1 1.5 1.5V17H3zM5 17v2M19 17v2" />
      <circle cx="7.5" cy="14.5" r="1" fill="currentColor" stroke="none" /><circle cx="16.5" cy="14.5" r="1" fill="currentColor" stroke="none" />
    </Icon>
  );
}

export function CheckCircleIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="m8.5 12.5 2.3 2.3L15.5 10" />
    </Icon>
  );
}

export function CheckIcon(props: IconProps) {
  return <Icon {...props}><path d="m5 12.5 4.2 4.2L19 7" /></Icon>;
}

export function CloseIcon(props: IconProps) {
  return <Icon {...props}><path d="M6 6l12 12M18 6 6 18" /></Icon>;
}

export function SteeringWheelIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="2.5" />
      <path d="M3.3 10.5c3-1.3 14.4-1.3 17.4 0M12 14.5V21M9.8 13.6 4.6 17.8M14.2 13.6l5.2 4.2" />
    </Icon>
  );
}

export function HomeIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M3.5 10.5 12 3.5l8.5 7" />
      <path d="M5.5 9v10.5a1 1 0 0 0 1 1h4v-6h3v6h4a1 1 0 0 0 1-1V9" />
    </Icon>
  );
}

export function UserIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <circle cx="12" cy="8" r="4" />
      <path d="M4.5 20.5a7.5 7.5 0 0 1 15 0" />
    </Icon>
  );
}
