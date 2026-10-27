export type Role = "CLIENT" | "COUNTER" | "CONTROLLER" | "ADMIN";

export interface User {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  phone: string;
  role: Role;
  role_display: string;
}

export interface Location {
  id: number;
  name: string;
  address: string;
  active: boolean;
}

export interface RouteStop {
  id: number;
  position: number;
  location_id: number;
  name: string;
  offset_minutes?: number | null;
}

export interface Route {
  id: number;
  origin: number;
  destination: number;
  origin_detail: Location;
  destination_detail: Location;
  label: string;
  stops?: RouteStop[];
  active: boolean;
}

export interface Vehicle {
  id: number;
  category: "BUS" | "RENTAL";
  category_display: string;
  name: string;
  registration_number: string | null;
  capacity: number | null;
  seat_configuration: Array<{ label: string; row?: number; column?: number }>;
  state: "ACTIVE" | "MAINTENANCE" | "UNAVAILABLE";
  state_display: string;
  base_location: number | null;
  base_location_detail?: Location;
  description: string;
  rental_daily_rate: string | null;
  driver_available: boolean;
}

export interface Fare {
  id: number;
  name: string;
  amount: string;
  currency: string;
}

export interface Trip {
  id: number;
  route: number;
  route_detail: Route;
  vehicle: number;
  vehicle_detail: Vehicle;
  departure_at: string;
  // Heure d'embarquement à l'origine, calculée par le serveur (départ − boarding_lead_minutes).
  boarding_at: string | null;
  arrival_at: string | null;
  status: string;
  status_display: string;
  note: string;
  available_seats: number;
  current_fare: Fare | null;
}

export interface WeeklySchedule {
  id: number;
  day_of_week: number;
  day_of_week_display: string;
  route: number | null;
  route_detail: Route | null;
  vehicle: number | null;
  vehicle_detail: Vehicle | null;
  departure_time: string | null;
  departure_time_display: string | null;
  is_active: boolean;
  notes: string;
}

export interface Seat {
  id: number;
  trip: number;
  number: string;
  row: number | null;
  column: number | null;
  status: "AVAILABLE" | "HELD" | "PAID";
  status_display: string;
  hold_expires_at: string | null;
}

export interface Ticket {
  id: number;
  reference: string;
  print_info?: TicketPrintInfo;
  booking?: number | null;
  trip: number;
  trip_detail: Trip;
  origin?: number | null;
  destination?: number | null;
  origin_name?: string;
  destination_name?: string;
  origin_detail?: Location;
  destination_detail?: Location;
  segment_label?: string;
  departure_label?: string;
  effective_departure_at?: string;
  seat: number;
  seat_detail: Seat;
  seat_preference?: boolean;
  seat_summary_label?: string;
  passenger_name: string;
  passenger_phone: string;
  status: string;
  status_display: string;
  qr_token: string;
  channel: string;
  channel_display: string;
  reservation_expires_at: string | null;
  amount: string;
  currency: string;
  created_at: string;
}

export interface BookingPassenger {
  id: number;
  full_name: string;
  phone: string;
  passenger_type: string;
  passenger_type_display: string;
}

export interface Booking {
  id: number;
  reference: string;
  trip: number;
  trip_detail: Trip;
  origin?: number | null;
  destination?: number | null;
  origin_name?: string;
  destination_name?: string;
  segment_label?: string;
  departure_label?: string;
  effective_departure_at?: string | null;
  contact_phone: string;
  buyer_ifu: string;
  status: "HELD" | "CONFIRMED" | "CANCELLED" | "EXPIRED" | "REFUND_DUE" | string;
  status_display: string;
  client_status_display?: string;
  reservation_expires_at: string | null;
  amount: string;
  currency: string;
  passengers: BookingPassenger[];
  tickets: Ticket[];
  payment_quotes: Array<{
    payment_method: number;
    label: string;
    amount: string | number;
    fee_amount: string | number;
    total: string | number;
    currency: string;
  }>;
  guest_access_token?: string;
  created_at: string;
}

export interface ParcelHistory {
  id: number;
  to_status: string;
  to_status_display: string;
  changed_at: string;
  changed_by_name: string;
}

export interface Parcel {
  id: number;
  tracking_number: string;
  sender_name: string;
  sender_phone: string;
  recipient_name: string;
  recipient_phone: string;
  origin: number;
  destination: number;
  origin_detail: Location;
  destination_detail: Location;
  trip: number | null;
  description: string;
  weight_kg: string | null;
  status: string;
  status_display: string;
  pickup_recipient_identity: string;
  status_history: ParcelHistory[];
}

export interface RentalBooking {
  id: number;
  reference: string;
  vehicle: number;
  vehicle_detail: Vehicle;
  starts_at: string;
  ends_at: string;
  with_driver: boolean;
  status: string;
  status_display: string;
}

export interface PaymentMethod {
  id: number;
  code: string;
  label: string;
  active: boolean;
  fee_percentage?: string | number;
  online?: boolean;
}

export interface ParcelTracking {
  tracking_number: string;
  origin: string;
  destination: string;
  current_step: string;
  steps: { key: string; label: string; done: boolean; current: boolean; reached_at: string | null }[];
}

export interface Contact {
  contact_phone: string;
  contact_whatsapp: string;
}

export interface Checkout {
  transaction_id: string;
  payment_url: string | null;
  simulated: boolean;
  payment_method: number;
  label: string;
  amount: string | number;
  fee_amount: string | number;
  total: string | number;
  currency: string;
}

export interface FeatureFlag {
  id: number;
  key: string;
  label: string;
  enabled: boolean;
  configuration: Record<string, unknown>;
}

export interface SegmentFare {
  id: number;
  label: string;
  start_name: string;
  end_name: string;
  amount: number;
  currency: string;
  updated_at: string;
  updated_by_name: string;
}

export interface SegmentFareChange {
  id: number;
  created_at: string;
  label: string;
  old_amount: number | null;
  new_amount: number;
  changed_by_name: string;
}

export interface AgencyInfo {
  legal_name: string;
  ifu: string;
  rccm: string;
  capital: string;
  address: string;
  phones: string;
  email: string;
}

export interface AgencyProfile extends AgencyInfo {
  bank_accounts: string;
  updated_at: string;
  updated_by_name: string;
}

export interface Tax {
  id: number;
  name: string;
  rate: string;
  active: boolean;
  included: boolean;
  updated_at: string;
}

export interface AgencySettingChange {
  id: number;
  changed_at: string;
  kind: "AGENCY" | "TAX";
  kind_display: string;
  label: string;
  old_value: Record<string, unknown> | null;
  new_value: Record<string, unknown>;
  changed_by_name: string;
}

export interface TicketPrintInfo {
  title: string;
  paid: boolean;
  sale: string;
  payment_mode: string;
  buyer_ifu: string;
  boarding_place: string;
  origin?: string;
  destination?: string;
  segment_label?: string;
  departure_label?: string;
  departure_at?: string;
  is_offset?: boolean;
  price_incl_tax: number;
  price_excl_tax: number | null;
  tax_lines: Array<{ name: string; rate: string; amount: number }>;
  agency: AgencyInfo;
  conditions: string;
}

export interface ManualTicketChange {
  id: number;
  changed_at: string;
  reference: string;
  from_status: string;
  from_status_display: string;
  to_status: string;
  to_status_display: string;
  changed_by_name: string;
  note: string;
}

export interface PaymentIncident {
  id: number;
  created_at: string;
  source_display: string;
  event: string;
  external_id: string;
  amount: string | null;
  currency: string;
  amount_verified: boolean;
  booking_reference: string;
  reason: string;
  handled: boolean;
}

export interface SystemSetting {
  id: number;
  key: string;
  value: unknown;
  description: string;
}

export interface FareRule {
  id: number;
  route: number;
  route_detail: Route;
  name: string;
  rule_type: "STANDARD" | "ADVANCE" | "SAME_DAY" | "PROMOTION";
  rule_type_display: string;
  amount: string;
  currency: string;
  advance_days: number | null;
  active: boolean;
}
