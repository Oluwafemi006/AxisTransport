export type Trip = {
  id: number;
  route: string;
  departure: string;
  arrival: string;
  time: string;
  price: string;
  seatsLeft: number;
};

export type Seat = {
  id: string;
  number: string;
  available: boolean;
};

export type ParcelItem = {
  id: number;
  route: string;
  status: string;
  progress: number;
  tracking: string;
};

export type Vehicle = {
  id: number;
  name: string;
  type: string;
  price: string;
  seats: number;
};

export const trips: Trip[] = [
  { id: 1, route: 'Cotonou → Parakou', departure: 'Cotonou', arrival: 'Parakou', time: '08:30', price: '7 500 F', seatsLeft: 14 },
  { id: 2, route: 'Parakou → Okédama', departure: 'Parakou', arrival: 'Okédama', time: '11:15', price: '5 200 F', seatsLeft: 8 },
  { id: 3, route: 'Okédama → Cotonou', departure: 'Okédama', arrival: 'Cotonou', time: '16:45', price: '7 500 F', seatsLeft: 21 },
];

export const seats: Seat[] = [
  { id: 'A1', number: 'A1', available: false },
  { id: 'A2', number: 'A2', available: true },
  { id: 'A3', number: 'A3', available: true },
  { id: 'A4', number: 'A4', available: false },
  { id: 'A5', number: 'A5', available: true },
  { id: 'A6', number: 'A6', available: true },
  { id: 'B1', number: 'B1', available: true },
  { id: 'B2', number: 'B2', available: false },
  { id: 'B3', number: 'B3', available: true },
  { id: 'B4', number: 'B4', available: true },
  { id: 'B5', number: 'B5', available: true },
  { id: 'B6', number: 'B6', available: false },
  { id: 'C1', number: 'C1', available: true },
  { id: 'C2', number: 'C2', available: true },
  { id: 'C3', number: 'C3', available: true },
  { id: 'C4', number: 'C4', available: false },
];

export const parcels: ParcelItem[] = [
  { id: 1, route: 'Cotonou → Parakou', status: 'En cours de transit', progress: 66, tracking: 'AX-2048' },
  { id: 2, route: 'Parakou → Okédama', status: 'Prêt à récupérer', progress: 100, tracking: 'AX-1054' },
];

export const vehicles: Vehicle[] = [
  { id: 1, name: 'Yutong 25', type: 'Van', price: '18 000 F/jour', seats: 20 },
  { id: 2, name: 'Hyundai 7', type: 'SUV', price: '26 000 F/jour', seats: 7 },
  { id: 3, name: 'Minibus', type: 'Transport', price: '14 500 F/jour', seats: 12 },
];

export const profileStats = [
  { label: 'Billets', value: '03' },
  { label: 'Colis', value: '02' },
  { label: 'Locations', value: '01' },
];
