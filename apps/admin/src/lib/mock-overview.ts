import type { OverviewMetrics } from "./api";

export const mockOverview: OverviewMetrics = {
  activeWaits: 18,
  activeVehicles: 9,
  routeCount: 12,
  boardedCount: 146,
  averageWaitMinutes: 7.8,
  ratingCount: 54,
  averageRating: 4.3,
  busiestRoutes: [
    {
      routeId: "mock-1",
      routeNameAr: "بغداد الجديدة - النهضة",
      waitCount: 38,
    },
    {
      routeId: "mock-2",
      routeNameAr: "الكاظمية - الوزيرية",
      waitCount: 27,
    },
    {
      routeId: "mock-3",
      routeNameAr: "الزعفرانية - بسماية",
      waitCount: 19,
    },
    {
      routeId: "mock-4",
      routeNameAr: "الباب الشرقي - الكرادة",
      waitCount: 14,
    },
  ],
};
