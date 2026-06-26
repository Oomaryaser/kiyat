export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:3000";

export type UserRole = "passenger" | "operator" | "admin" | "owner" | "support";

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

export interface OperatorProfile {
  id: string;
  phone: string;
  role: UserRole;
  nameAr: string | null;
}

export interface BusiestRoute {
  routeId: string;
  routeNameAr: string;
  waitCount: number;
}

export interface OverviewMetrics {
  activeWaits: number;
  activeVehicles: number;
  routeCount: number;
  boardedCount: number;
  averageWaitMinutes: number | null;
  ratingCount: number;
  averageRating: number | null;
  busiestRoutes: BusiestRoute[];
}

export interface LiveVehicle {
  id: string;
  driverName: string;
  routeId: string;
  routeName: string;
  lat: number;
  lng: number;
  lastSeenAt: string | null;
  speed: number;
  heading: number;
}

export interface PassengerWaitZone {
  id: string;
  routeId: string;
  routeName: string;
  lat: number;
  lng: number;
  updatedAt: string;
  count: number;
}

export interface LiveTrackingSummary {
  activeVehicles: number;
  waitingPassengers: number;
  passengerZones: number;
  updatedAt: string;
}

export interface LiveTrackingResponse {
  vehicles: LiveVehicle[];
  passengerWaits: PassengerWaitZone[];
  summary: LiveTrackingSummary;
}

export type RouteType = "kia" | "coaster" | "bus" | "minibus";
export type RouteStatus = "active" | "inactive" | "unverified";

export interface TransitRoute {
  id: string;
  nameAr: string;
  nameEn: string;
  routeType: RouteType;
  status: RouteStatus;
  fareMin: number;
  fareMax: number;
  operatingHoursStart: string;
  operatingHoursEnd: string;
  confidenceScore: number;
  lastVerifiedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TransitStop {
  id: string;
  nameAr: string;
  nameEn: string;
  location: {
    type: "Point";
    coordinates: [number, number];
  };
  landmarkAr: string | null;
  stopType: "fixed" | "approximate" | "informal";
}

export interface RouteStop {
  id: string;
  routeId: string;
  stopId: string;
  stopSequence: number;
  isMajor: boolean;
  stop: TransitStop;
}

export interface TransitRouteDetail extends TransitRoute {
  routeStops: RouteStop[];
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
}

export interface ListRoutesParams {
  page?: number;
  limit?: number;
  search?: string;
  status?: RouteStatus;
  type?: RouteType;
}

export interface ApiErrorPayload {
  message?: string | string[];
  statusCode?: number;
  error?: string;
}

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly payload?: ApiErrorPayload,
  ) {
    super(message);
  }
}

async function apiRequest<T>(
  path: string,
  options: RequestInit & { token?: string } = {},
): Promise<T> {
  const { token, headers, ...requestOptions } = options;
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...requestOptions,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
  });

  if (!response.ok) {
    let payload: ApiErrorPayload | undefined;
    try {
      payload = (await response.json()) as ApiErrorPayload;
    } catch {
      payload = undefined;
    }

    const message = Array.isArray(payload?.message)
      ? payload.message.join("، ")
      : payload?.message ?? "تعذر الاتصال بالخادم";
    throw new ApiError(message, response.status, payload);
  }

  return response.json() as Promise<T>;
}

export function sendOperatorOtp(phone: string) {
  return apiRequest<{ message: string }>("/auth/operator/login", {
    method: "POST",
    body: JSON.stringify({ phone }),
  });
}

export function verifyOperatorOtp(phone: string, otp: string) {
  return apiRequest<AuthTokens>("/auth/operator/verify-otp", {
    method: "POST",
    body: JSON.stringify({ phone, otp }),
  });
}

export function getOperatorProfile(token: string) {
  return apiRequest<OperatorProfile>("/auth/operator/me", { token });
}

export function getOverview(token: string) {
  return apiRequest<OverviewMetrics>("/analytics/overview", { token });
}

export function getLiveTracking(token: string) {
  return apiRequest<LiveTrackingResponse>("/analytics/live-tracking", { token });
}

export function getRoutes(token: string, params: ListRoutesParams = {}) {
  const searchParams = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== "") {
      searchParams.set(key, String(value));
    }
  }

  const queryString = searchParams.toString();
  return apiRequest<PaginatedResponse<TransitRoute>>(
    `/routes${queryString ? `?${queryString}` : ""}`,
    { token },
  );
}

export function getRouteDetail(token: string, routeId: string) {
  return apiRequest<TransitRouteDetail>(`/routes/${routeId}`, { token });
}
