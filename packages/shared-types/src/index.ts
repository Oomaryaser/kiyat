export enum RouteType {
  Kia = 'kia',
  Coaster = 'coaster',
  Bus = 'bus',
  Minibus = 'minibus',
}

export enum RouteStatus {
  Active = 'active',
  Inactive = 'inactive',
  Unverified = 'unverified',
}

export enum StopType {
  Fixed = 'fixed',
  Approximate = 'approximate',
  Informal = 'informal',
}

export enum UserRole {
  Passenger = 'passenger',
  Operator = 'operator',
  Admin = 'admin',
}

export enum ReportType {
  RouteChange = 'route_change',
  FareChange = 'fare_change',
  Closed = 'closed',
  NowRunning = 'now_running',
  Other = 'other',
}

export enum ReportStatus {
  Pending = 'pending',
  Approved = 'approved',
  Rejected = 'rejected',
}

export interface GeoPoint {
  type: 'Point';
  coordinates: [number, number];
}

export interface IRoute {
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

export interface IStop {
  id: string;
  nameAr: string;
  nameEn: string;
  location: GeoPoint;
  landmarkAr: string | null;
  stopType: StopType;
  createdAt: string;
  updatedAt: string;
}

export interface IRouteStop {
  id: string;
  routeId: string;
  stopId: string;
  stopSequence: number;
  isMajor: boolean;
  stop?: IStop;
}

export interface IVehicle {
  id: string;
  routeId: string;
  operatorId: string | null;
  plateNumber: string | null;
  lastLocation: GeoPoint | null;
  lastSeenAt: string | null;
  isTrackingActive: boolean;
}

export interface IUser {
  id: string;
  phone: string;
  role: UserRole;
  nameAr: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ICommunityReport {
  id: string;
  routeId: string;
  reporterId: string;
  reportType: ReportType;
  description: string;
  status: ReportStatus;
  reviewedById: string | null;
  createdAt: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
}

export interface ApiResponse<T> {
  data: T;
  message?: string;
}
