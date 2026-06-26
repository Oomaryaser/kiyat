"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  AlertCircle,
  Bus,
  Clock3,
  type LucideIcon,
  MapPinned,
  Navigation,
  Users,
} from "lucide-react";
import {
  getLiveTracking,
  getRouteDetail,
  type LiveTrackingResponse,
  type TransitRouteDetail,
} from "@/lib/api";
import { loadGoogleMaps } from "@/lib/google-maps-loader";
import { mockLiveTracking, mockRouteLines } from "@/lib/mock-sprint-two";

interface LiveMapPanelProps {
  token?: string;
  isDemo: boolean;
}

interface LatLngPoint {
  lat: number;
  lng: number;
}

interface RouteStopPoint extends LatLngPoint {
  name: string;
}

interface RouteLine {
  routeId: string;
  routeName: string;
  color: string;
  fromName: string;
  toName: string;
  points: LatLngPoint[];
  stops: RouteStopPoint[];
}

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY ?? "";
const baghdadCenter = { lat: 33.3152, lng: 44.3661 };
const routeColors = ["#1b5e8b", "#24605c", "#7c3aed", "#b45309", "#be123c"];
const cleanMapStyle: google.maps.MapTypeStyle[] = [
  {
    featureType: "poi",
    elementType: "labels.icon",
    stylers: [{ visibility: "off" }],
  },
  {
    featureType: "poi.business",
    stylers: [{ visibility: "off" }],
  },
  {
    featureType: "transit.station",
    elementType: "labels.icon",
    stylers: [{ visibility: "off" }],
  },
];

export function LiveMapPanel({ token, isDemo }: LiveMapPanelProps) {
  const mapContainerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<google.maps.Map | null>(null);
  const markerRefs = useRef<google.maps.Marker[]>([]);
  const circleRefs = useRef<google.maps.Circle[]>([]);
  const polylineRefs = useRef<google.maps.Polyline[]>([]);
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);
  const [roadRouteLines, setRoadRouteLines] = useState<RouteLine[]>([]);
  const [isResolvingRoutes, setIsResolvingRoutes] = useState(false);
  const [routePathError, setRoutePathError] = useState<string | null>(null);

  const liveQuery = useQuery({
    queryKey: ["live-tracking", token],
    queryFn: () => getLiveTracking(token ?? ""),
    enabled: Boolean(token) && !isDemo,
    refetchInterval: 30_000,
  });

  const tracking = liveQuery.data ?? mockLiveTracking;
  const liveRouteIds = useMemo(
    () =>
      Array.from(
        new Set([
          ...tracking.vehicles.map((vehicle) => vehicle.routeId),
          ...tracking.passengerWaits.map((zone) => zone.routeId),
        ]),
      ),
    [tracking],
  );
  const routeDetailsQuery = useQuery({
    queryKey: ["live-route-details", token, liveRouteIds.join(",")],
    queryFn: () =>
      Promise.all(
        liveRouteIds.map((routeId) => getRouteDetail(token ?? "", routeId)),
      ),
    enabled:
      Boolean(token) &&
      !isDemo &&
      Boolean(liveQuery.data) &&
      liveRouteIds.length > 0,
  });
  const nearestZoneId = useMemo(
    () => nearestPassengerZoneId(tracking),
    [tracking],
  );
  const routeLines = useMemo(
    () =>
      isDemo || !liveQuery.data
        ? buildMockRouteLines(liveRouteIds)
        : buildBackendRouteLines(routeDetailsQuery.data ?? []),
    [isDemo, liveQuery.data, liveRouteIds, routeDetailsQuery.data],
  );
  const listedRouteLines = roadRouteLines.length > 0 ? roadRouteLines : routeLines;

  useEffect(() => {
    let mounted = true;

    async function setupMap() {
      if (!mapContainerRef.current || mapRef.current) return;
      if (!googleMapsApiKey) {
        setMapError("أضف NEXT_PUBLIC_GOOGLE_MAPS_API_KEY حتى تظهر خريطة Google.");
        return;
      }

      try {
        const maps = await loadGoogleMaps(googleMapsApiKey);
        if (!mounted || !mapContainerRef.current) return;

        mapRef.current = new maps.Map(mapContainerRef.current, {
          center: baghdadCenter,
          zoom: 12,
          mapTypeId: maps.MapTypeId.ROADMAP,
          styles: cleanMapStyle,
          disableDefaultUI: false,
          fullscreenControl: false,
          mapTypeControl: false,
          streetViewControl: false,
          zoomControl: true,
          clickableIcons: false,
          gestureHandling: "greedy",
        });
        setMapReady(true);
      } catch {
        if (mounted) setMapError("تعذر تحميل Google Maps.");
      }
    }

    void setupMap();

    return () => {
      mounted = false;
      clearMapObjects();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (!mapReady || routeLines.length === 0) {
      setRoadRouteLines([]);
      setRoutePathError(null);
      setIsResolvingRoutes(false);
      return;
    }

    let cancelled = false;
    setIsResolvingRoutes(true);
    setRoutePathError(null);
    setRoadRouteLines([]);

    resolveRoadRouteLines(routeLines)
      .then((resolvedLines) => {
        if (cancelled) return;
        setRoadRouteLines(resolvedLines);
        if (resolvedLines.length < routeLines.length) {
          setRoutePathError(
            "بعض الطرق ما انحسبت كمسار شارع من Google Directions.",
          );
        }
      })
      .catch(() => {
        if (cancelled) return;
        setRoadRouteLines([]);
        setRoutePathError(
          "تعذر حساب طريق الشارع من Google Directions. تأكد من تفعيل Directions API على نفس المفتاح.",
        );
      })
      .finally(() => {
        if (!cancelled) setIsResolvingRoutes(false);
      });

    return () => {
      cancelled = true;
    };
  }, [mapReady, routeLines]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    clearMapObjects();
    const bounds = new google.maps.LatLngBounds();

    for (const routeLine of roadRouteLines) {
      if (routeLine.points.length < 2) continue;
      routeLine.points.forEach((point) => bounds.extend(point));
      drawRouteLine(map, routeLine);
    }

    for (const [index, zone] of tracking.passengerWaits.entries()) {
      const isNearest = zone.id === nearestZoneId;
      const position = { lat: zone.lat, lng: zone.lng };
      bounds.extend(position);
      circleRefs.current.push(
        new google.maps.Circle({
          map,
          center: position,
          radius: isNearest ? 85 : 58,
          fillColor: "#ff9800",
          fillOpacity: isNearest ? 0.18 : 0.1,
          strokeColor: isNearest ? "#e65100" : "#1b5e8b",
          strokeOpacity: isNearest ? 0.92 : 0.5,
          strokeWeight: isNearest ? 3 : 2,
          zIndex: isNearest ? 8 : 4,
        }),
      );
      markerRefs.current.push(
        new google.maps.Marker({
          map,
          position,
          icon: {
            url: buildPassengerIcon(zone.count, isNearest),
            scaledSize: new google.maps.Size(40, 40),
            anchor: new google.maps.Point(20, 20),
          },
          title: isNearest
            ? `روح لهنا • ${zone.count} ركاب`
            : `${zone.count} ركاب ينتظرون`,
          zIndex: isNearest ? 30 : 20 + index,
        }),
      );
    }

    for (const [index, vehicle] of tracking.vehicles.entries()) {
      const position = { lat: vehicle.lat, lng: vehicle.lng };
      bounds.extend(position);
      circleRefs.current.push(
        new google.maps.Circle({
          map,
          center: position,
          radius: 70,
          fillColor: "#1b5e8b",
          fillOpacity: 0.12,
          strokeColor: "#1b5e8b",
          strokeOpacity: 0.34,
          strokeWeight: 2,
          zIndex: 6,
        }),
      );
      markerRefs.current.push(
        new google.maps.Marker({
          map,
          position,
          icon: {
            url: buildVehicleIcon(index + 1),
            scaledSize: new google.maps.Size(68, 50),
            anchor: new google.maps.Point(34, 42),
          },
          title: `${vehicle.driverName} - ${vehicle.routeName}`,
          zIndex: 40 + index,
        }),
      );
    }

    if (!bounds.isEmpty()) {
      map.fitBounds(bounds, 78);
      const listener = google.maps.event.addListenerOnce(map, "idle", () => {
        if ((map.getZoom() ?? 0) > 15) map.setZoom(15);
      });
      return () => google.maps.event.removeListener(listener);
    }
  }, [mapReady, nearestZoneId, roadRouteLines, tracking]);

  function drawRouteLine(map: google.maps.Map, routeLine: RouteLine) {
    polylineRefs.current.push(
      new google.maps.Polyline({
        map,
        path: routeLine.points,
        strokeColor: "#ffffff",
        strokeOpacity: 0.9,
        strokeWeight: 10,
        zIndex: 1,
      }),
    );
    polylineRefs.current.push(
      new google.maps.Polyline({
        map,
        path: routeLine.points,
        strokeColor: routeLine.color,
        strokeOpacity: 0.88,
        strokeWeight: 5,
        zIndex: 2,
        icons: [
          {
            icon: {
              path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
              scale: 3,
              strokeColor: routeLine.color,
              fillColor: routeLine.color,
              fillOpacity: 1,
            },
            offset: "55%",
            repeat: "180px",
          },
        ],
      }),
    );

    const fromPoint = routeLine.stops[0] ?? routeLine.points[0];
    const toPoint =
      routeLine.stops[routeLine.stops.length - 1] ??
      routeLine.points[routeLine.points.length - 1];
    routeLine.stops.slice(1, -1).forEach((point) => {
      markerRefs.current.push(
        new google.maps.Marker({
          map,
          position: point,
          icon: {
            url: buildRouteDotIcon(routeLine.color),
            scaledSize: new google.maps.Size(18, 18),
            anchor: new google.maps.Point(9, 9),
          },
          zIndex: 11,
        }),
      );
    });
    markerRefs.current.push(
      new google.maps.Marker({
        map,
        position: fromPoint,
        icon: {
          url: buildRoutePointIcon("من", routeLine.color),
          scaledSize: new google.maps.Size(58, 38),
          anchor: new google.maps.Point(29, 38),
        },
        title: `من ${routeLine.fromName}`,
        zIndex: 24,
      }),
    );
    markerRefs.current.push(
      new google.maps.Marker({
        map,
        position: toPoint,
        icon: {
          url: buildRoutePointIcon("إلى", routeLine.color),
          scaledSize: new google.maps.Size(58, 38),
          anchor: new google.maps.Point(29, 38),
        },
        title: `إلى ${routeLine.toName}`,
        zIndex: 24,
      }),
    );
  }

  function clearMapObjects() {
    markerRefs.current.forEach((marker) => marker.setMap(null));
    circleRefs.current.forEach((circle) => circle.setMap(null));
    polylineRefs.current.forEach((polyline) => polyline.setMap(null));
    markerRefs.current = [];
    circleRefs.current = [];
    polylineRefs.current = [];
  }

  function focusMap(lat: number, lng: number, zoom = 16) {
    mapRef.current?.panTo({ lat, lng });
    mapRef.current?.setZoom(zoom);
  }

  function focusRoute(routeLine: RouteLine) {
    const map = mapRef.current;
    if (!map || routeLine.points.length === 0) return;
    const bounds = new google.maps.LatLngBounds();
    routeLine.points.forEach((point) => bounds.extend(point));
    map.fitBounds(bounds, 90);
  }

  return (
    <section className="page-stack" aria-label="الخريطة الحية">
      <div className="section-head">
        <div>
          <p className="eyebrow">Live Map</p>
          <h2>الخريطة الحية</h2>
        </div>
        <span className="status-chip">{liveQuery.data ? "مباشر" : "تجريبي"}</span>
      </div>

      {liveQuery.isError ? (
        <div className="inline-alert">
          <AlertCircle aria-hidden="true" size={18} />
          <span>تعذر جلب بيانات الخريطة الحية، تظهر بيانات تجريبية مؤقتاً.</span>
        </div>
      ) : null}
      {routePathError ? (
        <div className="inline-alert">
          <AlertCircle aria-hidden="true" size={18} />
          <span>{routePathError}</span>
        </div>
      ) : null}

      <div className="metric-grid live-summary-grid">
        <SmallStat
          icon={Bus}
          label="مركبات نشطة"
          value={tracking.summary.activeVehicles}
        />
        <SmallStat
          icon={Users}
          label="ركاب منتظرين"
          value={tracking.summary.waitingPassengers}
        />
        <SmallStat
          icon={MapPinned}
          label="مناطق انتظار"
          value={tracking.summary.passengerZones}
        />
        <SmallStat
          icon={Clock3}
          label="آخر تحديث"
          value={formatTime(tracking.summary.updatedAt)}
        />
      </div>

      <div className="map-layout">
        <section className="panel map-panel" aria-label="خريطة بغداد">
          <div ref={mapContainerRef} className="live-map-canvas" />
          {isResolvingRoutes ? (
            <div className="map-route-loading">حساب مسارات الشوارع</div>
          ) : null}
          <div className="map-legend">
            <span>
              <i className="legend-line" />
              الخط
            </span>
            <span>
              <i className="legend-dot legend-vehicle" />
              كية نشطة
            </span>
            <span>
              <i className="legend-dot legend-zone-nearest" />
              أقرب انتظار
            </span>
            <span>
              <i className="legend-dot legend-zone" />
              انتظار
            </span>
          </div>
          {mapError ? <div className="map-loading">{mapError}</div> : null}
          {!mapReady && !mapError ? (
            <div className="map-loading">تحميل خريطة Google</div>
          ) : null}
        </section>

        <section className="panel map-side-panel" aria-labelledby="vehicle-list-title">
          <div className="panel-head">
            <h3>الخطوط على الخريطة</h3>
            <span>{routeLines.length} خطوط</span>
          </div>
          <div className="route-map-list">
            {listedRouteLines.map((routeLine) => (
              <button
                className="route-map-row"
                key={routeLine.routeId}
                type="button"
                onClick={() => focusRoute(routeLine)}
              >
                <span
                  className="route-color-line"
                  style={{ background: routeLine.color, color: routeLine.color }}
                />
                <div>
                  <strong>{routeLine.routeName}</strong>
                  <span>
                    من {routeLine.fromName} إلى {routeLine.toName}
                  </span>
                </div>
              </button>
            ))}
          </div>

          <div className="panel-head zone-head">
            <h3 id="vehicle-list-title">المركبات النشطة</h3>
            <span>{tracking.vehicles.length} مركبات</span>
          </div>
          <div className="vehicle-list">
            {tracking.vehicles.map((vehicle) => (
              <button
                className="vehicle-row"
                key={vehicle.id}
                type="button"
                onClick={() => focusMap(vehicle.lat, vehicle.lng)}
              >
                <Navigation aria-hidden="true" size={18} />
                <div>
                  <strong>{vehicle.driverName}</strong>
                  <span>{vehicle.routeName}</span>
                </div>
                <small>{formatSpeed(vehicle.speed)}</small>
              </button>
            ))}
          </div>

          <div className="panel-head zone-head">
            <h3>مناطق الانتظار</h3>
            <span>{tracking.passengerWaits.length} مناطق</span>
          </div>
          <div className="vehicle-list">
            {tracking.passengerWaits.map((zone) => {
              const isNearest = zone.id === nearestZoneId;
              return (
                <button
                  className="vehicle-row zone-row"
                  key={zone.id}
                  type="button"
                  onClick={() => focusMap(zone.lat, zone.lng)}
                >
                  <span className={isNearest ? "wait-dot nearest" : "wait-dot"}>
                    {zone.count}
                  </span>
                  <div>
                    <strong>{isNearest ? `روح لهنا • ${zone.routeName}` : zone.routeName}</strong>
                    <span>{formatTime(zone.updatedAt)}</span>
                  </div>
                  <small>{zone.count} ركاب</small>
                </button>
              );
            })}
          </div>
        </section>
      </div>
    </section>
  );
}

function SmallStat({
  icon: Icon,
  label,
  value,
}: {
  icon: LucideIcon;
  label: string;
  value: string | number;
}) {
  return (
    <article className="small-stat">
      <Icon aria-hidden="true" size={18} />
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

function buildMockRouteLines(routeIds: string[]) {
  const selectedRouteIds = new Set(routeIds);
  return mockRouteLines
    .filter((routeLine) => selectedRouteIds.has(routeLine.routeId))
    .map<RouteLine>((routeLine) => {
      const stops = routeLine.stops.map((stop) => ({
        lat: stop.lat,
        lng: stop.lng,
        name: stop.nameAr,
      }));

      return {
        routeId: routeLine.routeId,
        routeName: routeLine.routeName,
        color: routeLine.color,
        fromName: routeLine.stops[0]?.nameAr ?? "بداية الخط",
        toName:
          routeLine.stops[routeLine.stops.length - 1]?.nameAr ?? "نهاية الخط",
        points: stops,
        stops,
      };
    });
}

function buildBackendRouteLines(routes: TransitRouteDetail[]) {
  return routes
    .map<RouteLine | null>((route, index) => {
      const sortedStops = [...(route.routeStops ?? [])].sort(
        (a, b) => a.stopSequence - b.stopSequence,
      );
      const stops = sortedStops
        .map((routeStop) => {
          const coordinates = routeStop.stop?.location?.coordinates;
          if (!coordinates) return null;
          return {
            lat: coordinates[1],
            lng: coordinates[0],
            name: routeStop.stop?.nameAr ?? "توقف",
          };
        })
        .filter((point): point is RouteStopPoint => Boolean(point));

      if (stops.length < 2) return null;

      return {
        routeId: route.id,
        routeName: route.nameAr,
        color: routeColors[index % routeColors.length],
        fromName: sortedStops[0]?.stop?.nameAr ?? "بداية الخط",
        toName: sortedStops[sortedStops.length - 1]?.stop?.nameAr ?? "نهاية الخط",
        points: stops,
        stops,
      };
    })
    .filter((routeLine): routeLine is RouteLine => Boolean(routeLine));
}

async function resolveRoadRouteLines(routeLines: RouteLine[]) {
  const service = new google.maps.DirectionsService();
  const resolvedLines: RouteLine[] = [];

  for (const routeLine of routeLines) {
    try {
      const roadPath = await requestRoadPath(service, routeLine.stops);
      if (roadPath.length >= 2) {
        resolvedLines.push({ ...routeLine, points: roadPath });
      }
    } catch {
      // Keep the map honest: if Google cannot calculate a road route,
      // do not fall back to a fake straight line.
    }
  }

  return resolvedLines;
}

async function requestRoadPath(
  service: google.maps.DirectionsService,
  stops: RouteStopPoint[],
) {
  const roadPath: LatLngPoint[] = [];
  const chunks = buildStopChunks(stops, 25);

  for (const chunk of chunks) {
    const segmentPath = await requestDirectionsSegment(service, chunk);
    appendPath(roadPath, segmentPath);
  }

  return roadPath;
}

function buildStopChunks(stops: RouteStopPoint[], maxStopsPerChunk: number) {
  const chunks: RouteStopPoint[][] = [];
  const step = Math.max(maxStopsPerChunk, 2) - 1;

  for (let start = 0; start < stops.length - 1; start += step) {
    const end = Math.min(stops.length, start + maxStopsPerChunk);
    const chunk = stops.slice(start, end);
    if (chunk.length >= 2) chunks.push(chunk);
    if (end === stops.length) break;
  }

  return chunks;
}

function requestDirectionsSegment(
  service: google.maps.DirectionsService,
  stops: RouteStopPoint[],
) {
  const origin = stops[0];
  const destination = stops[stops.length - 1];

  return new Promise<LatLngPoint[]>((resolve, reject) => {
    service.route(
      {
        origin,
        destination,
        waypoints: stops.slice(1, -1).map((stop) => ({
          location: stop,
          stopover: true,
        })),
        optimizeWaypoints: false,
        provideRouteAlternatives: false,
        travelMode: google.maps.TravelMode.DRIVING,
      },
      (result, status) => {
        if (status !== google.maps.DirectionsStatus.OK || !result) {
          reject(new Error(status));
          return;
        }

        resolve(extractDirectionsPath(result));
      },
    );
  });
}

function extractDirectionsPath(result: google.maps.DirectionsResult) {
  const route = result.routes[0];
  const stepPath =
    route?.legs.flatMap((leg) =>
      leg.steps.flatMap((step) => step.path.map(latLngToPoint)),
    ) ?? [];

  if (stepPath.length >= 2) return stepPath;
  return route?.overview_path.map(latLngToPoint) ?? [];
}

function appendPath(target: LatLngPoint[], source: LatLngPoint[]) {
  for (const point of source) {
    const previous = target[target.length - 1];
    if (previous && samePoint(previous, point)) continue;
    target.push(point);
  }
}

function samePoint(first: LatLngPoint, second: LatLngPoint) {
  return (
    Math.abs(first.lat - second.lat) < 0.000001 &&
    Math.abs(first.lng - second.lng) < 0.000001
  );
}

function latLngToPoint(latLng: google.maps.LatLng) {
  return { lat: latLng.lat(), lng: latLng.lng() };
}

function nearestPassengerZoneId(tracking: LiveTrackingResponse) {
  const firstVehicle = tracking.vehicles[0];
  if (!firstVehicle || tracking.passengerWaits.length === 0) return null;

  return [...tracking.passengerWaits].sort((a, b) => {
    const distanceA = distanceBetween(firstVehicle.lat, firstVehicle.lng, a.lat, a.lng);
    const distanceB = distanceBetween(firstVehicle.lat, firstVehicle.lng, b.lat, b.lng);
    return distanceA - distanceB;
  })[0].id;
}

function buildRoutePointIcon(text: string, color: string) {
  return svgDataUrl(`
    <svg xmlns="http://www.w3.org/2000/svg" width="116" height="76" viewBox="0 0 116 76">
      <filter id="shadow" x="-40%" y="-40%" width="180%" height="180%">
        <feDropShadow dx="0" dy="4" stdDeviation="4" flood-color="rgba(15,23,42,0.22)"/>
      </filter>
      <path d="M58 72 L47 56 H69 Z" fill="${color}"/>
      <rect x="18" y="10" width="80" height="48" rx="18" fill="${color}" stroke="#fff" stroke-width="5" filter="url(#shadow)"/>
      <text x="58" y="42" text-anchor="middle" font-size="24" font-family="Arial, sans-serif" font-weight="900" fill="#fff">${text}</text>
    </svg>
  `);
}

function buildRouteDotIcon(color: string) {
  return svgDataUrl(`
    <svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36">
      <circle cx="18" cy="18" r="12" fill="${color}" stroke="#fff" stroke-width="6"/>
    </svg>
  `);
}

function buildPassengerIcon(count: number, isNearest: boolean) {
  const mainColor = isNearest ? "#ff5722" : "#1b5e8b";
  const glowColor = isNearest ? "rgba(255,87,34,0.38)" : "rgba(0,0,0,0.18)";
  return svgDataUrl(`
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
      <filter id="shadow" x="-40%" y="-40%" width="180%" height="180%">
        <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="${glowColor}"/>
      </filter>
      <circle cx="32" cy="32" r="28" fill="${glowColor}"/>
      <circle cx="32" cy="32" r="22" fill="#fff" filter="url(#shadow)"/>
      <circle cx="32" cy="32" r="17" fill="${mainColor}"/>
      <text x="32" y="38" text-anchor="middle" font-size="18" font-family="Arial, sans-serif" font-weight="900" fill="#fff">${count}</text>
    </svg>
  `);
}

function buildVehicleIcon(index: number) {
  return svgDataUrl(`
    <svg xmlns="http://www.w3.org/2000/svg" width="112" height="82" viewBox="0 0 112 82">
      <filter id="shadow" x="-40%" y="-40%" width="180%" height="180%">
        <feDropShadow dx="0" dy="5" stdDeviation="5" flood-color="rgba(0,0,0,0.22)"/>
      </filter>
      <rect x="16" y="18" width="80" height="44" rx="14" fill="#1b5e8b" stroke="#fff" stroke-width="4" filter="url(#shadow)"/>
      <path d="M32 18 L48 6 H72 L88 18 Z" fill="#24605c"/>
      <rect x="34" y="24" width="18" height="14" rx="4" fill="rgba(255,255,255,0.92)"/>
      <rect x="60" y="24" width="18" height="14" rx="4" fill="rgba(255,255,255,0.92)"/>
      <circle cx="34" cy="62" r="8" fill="#fff"/>
      <circle cx="78" cy="62" r="8" fill="#fff"/>
      <circle cx="34" cy="62" r="4" fill="#24605c"/>
      <circle cx="78" cy="62" r="4" fill="#24605c"/>
      <text x="56" y="55" text-anchor="middle" font-size="17" font-family="Arial, sans-serif" font-weight="900" fill="#fff">كية ${index}</text>
    </svg>
  `);
}

function svgDataUrl(svg: string) {
  return `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`;
}

function distanceBetween(
  latA: number,
  lngA: number,
  latB: number,
  lngB: number,
) {
  const latDistance = latA - latB;
  const lngDistance = lngA - lngB;
  return Math.sqrt(latDistance * latDistance + lngDistance * lngDistance);
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat("ar-IQ", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

function formatSpeed(value: number) {
  const kmh = value * 3.6;
  return `${kmh.toFixed(0)} كم/س`;
}
