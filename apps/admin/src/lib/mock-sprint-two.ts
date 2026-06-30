import type {
  LiveTrackingResponse,
  PaginatedResponse,
  TransitRoute,
} from "./api";

const now = new Date().toISOString();

export const mockLiveTracking: LiveTrackingResponse = {
  vehicles: [
    {
      id: "vehicle-demo-1",
      driverName: "سائق كية ١",
      routeId: "route-demo-1",
      routeName: "بغداد الجديدة - النهضة",
      lat: 33.3238,
      lng: 44.4569,
      lastSeenAt: now,
      speed: 8.4,
      heading: 312,
    },
    {
      id: "vehicle-demo-2",
      driverName: "سائق كية ٢",
      routeId: "route-demo-2",
      routeName: "الكاظمية - الوزيرية",
      lat: 33.3601,
      lng: 44.3656,
      lastSeenAt: now,
      speed: 6.1,
      heading: 96,
    },
    {
      id: "vehicle-demo-3",
      driverName: "سائق كية ٣",
      routeId: "route-demo-3",
      routeName: "الزعفرانية - بسماية",
      lat: 33.2528,
      lng: 44.5361,
      lastSeenAt: now,
      speed: 7.6,
      heading: 138,
    },
  ],
  passengerWaits: [
    {
      id: "zone-demo-1",
      routeId: "route-demo-1",
      routeName: "بغداد الجديدة - النهضة",
      lat: 33.336,
      lng: 44.444,
      updatedAt: now,
      count: 7,
    },
    {
      id: "zone-demo-2",
      routeId: "route-demo-2",
      routeName: "الكاظمية - الوزيرية",
      lat: 33.356,
      lng: 44.393,
      updatedAt: now,
      count: 4,
    },
    {
      id: "zone-demo-3",
      routeId: "route-demo-3",
      routeName: "الزعفرانية - بسماية",
      lat: 33.236,
      lng: 44.493,
      updatedAt: now,
      count: 5,
    },
  ],
  summary: {
    activeVehicles: 3,
    waitingPassengers: 16,
    passengerZones: 3,
    updatedAt: now,
  },
};

export const mockRoutes: PaginatedResponse<TransitRoute> = {
  page: 1,
  limit: 50,
  total: 5,
  data: [
    {
      id: "route-demo-1",
      nameAr: "بغداد الجديدة - النهضة",
      nameEn: "New Baghdad - Al-Nahdha",
      routeType: "kia",
      status: "active",
      fareMin: 500,
      fareMax: 1000,
      operatingHoursStart: "06:00",
      operatingHoursEnd: "22:00",
      confidenceScore: 78,
      lastVerifiedAt: now,
      routePath: null,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: "route-demo-2",
      nameAr: "اختبار شمال بغداد - الكاظمية",
      nameEn: "Test North Baghdad - Kadhimiya",
      routeType: "kia",
      status: "active",
      fareMin: 500,
      fareMax: 1000,
      operatingHoursStart: "06:00",
      operatingHoursEnd: "22:00",
      confidenceScore: 74,
      lastVerifiedAt: now,
      routePath: null,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: "route-demo-3",
      nameAr: "اختبار جنوب بغداد - الزعفرانية",
      nameEn: "Test South Baghdad - Zafaraniya",
      routeType: "coaster",
      status: "active",
      fareMin: 750,
      fareMax: 1250,
      operatingHoursStart: "06:30",
      operatingHoursEnd: "21:30",
      confidenceScore: 69,
      lastVerifiedAt: now,
      routePath: null,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: "route-demo-4",
      nameAr: "الباب الشرقي - الكرادة",
      nameEn: "Bab Al-Sharqi - Karrada",
      routeType: "kia",
      status: "unverified",
      fareMin: 500,
      fareMax: 1000,
      operatingHoursStart: "07:00",
      operatingHoursEnd: "20:30",
      confidenceScore: 45,
      lastVerifiedAt: null,
      routePath: null,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: "route-demo-5",
      nameAr: "المنصور - الجامعة",
      nameEn: "Mansour - Al-Jamiaa",
      routeType: "minibus",
      status: "inactive",
      fareMin: 500,
      fareMax: 1000,
      operatingHoursStart: "08:00",
      operatingHoursEnd: "18:00",
      confidenceScore: 38,
      lastVerifiedAt: null,
      routePath: null,
      createdAt: now,
      updatedAt: now,
    },
  ],
};

export interface MockRouteLine {
  routeId: string;
  routeName: string;
  color: string;
  path?: Array<{ lat: number; lng: number }>;
  stops: Array<{
    nameAr: string;
    lat: number;
    lng: number;
  }>;
}

export const mockRouteLines: MockRouteLine[] = [
  {
    routeId: "route-demo-1",
    routeName: "بغداد الجديدة - النهضة",
    color: "#202a38",
    path: [
      { lat: 33.3009, lng: 44.4927 },
      { lat: 33.3064, lng: 44.4849 },
      { lat: 33.3126, lng: 44.4758 },
      { lat: 33.3191, lng: 44.4655 },
      { lat: 33.3238, lng: 44.4569 },
      { lat: 33.3298, lng: 44.4517 },
      { lat: 33.3362, lng: 44.4442 },
      { lat: 33.3412, lng: 44.4342 },
      { lat: 33.3446, lng: 44.4224 },
    ],
    stops: [
      { nameAr: "بغداد الجديدة", lat: 33.3009, lng: 44.4927 },
      { nameAr: "شارع فلسطين", lat: 33.3238, lng: 44.4569 },
      { nameAr: "ساحة بيروت", lat: 33.3362, lng: 44.4442 },
      { nameAr: "النهضة", lat: 33.3446, lng: 44.4224 },
    ],
  },
  {
    routeId: "route-demo-2",
    routeName: "الكاظمية - الوزيرية",
    color: "#2ecc71",
    path: [
      { lat: 33.3792, lng: 44.3384 },
      { lat: 33.3729, lng: 44.3474 },
      { lat: 33.3662, lng: 44.3549 },
      { lat: 33.3601, lng: 44.3656 },
      { lat: 33.3577, lng: 44.3749 },
      { lat: 33.3565, lng: 44.3927 },
    ],
    stops: [
      { nameAr: "الكاظمية", lat: 33.3792, lng: 44.3384 },
      { nameAr: "العطيفية", lat: 33.3601, lng: 44.3656 },
      { nameAr: "الوزيرية", lat: 33.3565, lng: 44.3927 },
    ],
  },
  {
    routeId: "route-demo-3",
    routeName: "الزعفرانية - بسماية",
    color: "#7c3aed",
    path: [
      { lat: 33.2357, lng: 44.4929 },
      { lat: 33.2424, lng: 44.5059 },
      { lat: 33.2497, lng: 44.5217 },
      { lat: 33.2528, lng: 44.5361 },
      { lat: 33.2357, lng: 44.5593 },
      { lat: 33.2131, lng: 44.5837 },
      { lat: 33.181, lng: 44.6065 },
    ],
    stops: [
      { nameAr: "الزعفرانية", lat: 33.2357, lng: 44.4929 },
      { nameAr: "جسر ديالى", lat: 33.2528, lng: 44.5361 },
      { nameAr: "بسماية", lat: 33.181, lng: 44.6065 },
    ],
  },
];
