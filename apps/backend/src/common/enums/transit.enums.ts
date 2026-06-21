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

export enum PassengerWaitStatus {
  Waiting = 'waiting',
  Boarded = 'boarded',
  Cancelled = 'cancelled',
}

export enum TripCrowdingLevel {
  Low = 'low',
  Medium = 'medium',
  High = 'high',
}
