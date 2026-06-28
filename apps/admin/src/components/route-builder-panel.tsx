"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import {
  AlertCircle,
  Check,
  MapPinned,
  RotateCcw,
  Route as RouteIcon,
  Save,
  Trash2,
  X,
} from "lucide-react";
import {
  createRoute,
  type CreateRoutePayload,
  type RoutePathPoint,
  type RouteStatus,
  type RouteType,
  type TransitRoute,
} from "@/lib/api";
import { loadGoogleMaps } from "@/lib/google-maps-loader";

interface RouteBuilderPanelProps {
  token?: string;
  isDemo: boolean;
  onCreated: (route: TransitRoute) => void;
  onCancel: () => void;
}

interface RouteFormState {
  nameAr: string;
  nameEn: string;
  routeType: RouteType;
  status: RouteStatus;
  fareMin: string;
  fareMax: string;
  operatingHoursStart: string;
  operatingHoursEnd: string;
}

interface RouteOption {
  id: string;
  summary: string;
  distanceText: string;
  durationText: string;
  points: RoutePathPoint[];
}

type EndpointTarget = "origin" | "destination";

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY ?? "";
const baghdadCenter = { lat: 33.3152, lng: 44.3661 };
const initialFormState: RouteFormState = {
  nameAr: "",
  nameEn: "",
  routeType: "kia",
  status: "active",
  fareMin: "500",
  fareMax: "1000",
  operatingHoursStart: "06:00",
  operatingHoursEnd: "22:00",
};

export function RouteBuilderPanel({
  token,
  isDemo,
  onCreated,
  onCancel,
}: RouteBuilderPanelProps) {
  const mapContainerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<google.maps.Map | null>(null);
  const markerRefs = useRef<google.maps.Marker[]>([]);
  const polylineRefs = useRef<google.maps.Polyline[]>([]);
  const selectionTargetRef = useRef<EndpointTarget>("origin");
  const [form, setForm] = useState<RouteFormState>(initialFormState);
  const [selectionTarget, setSelectionTarget] = useState<EndpointTarget>("origin");
  const [originPoint, setOriginPoint] = useState<RoutePathPoint | null>(null);
  const [destinationPoint, setDestinationPoint] = useState<RoutePathPoint | null>(
    null,
  );
  const [routePath, setRoutePath] = useState<RoutePathPoint[]>([]);
  const [routeOptions, setRouteOptions] = useState<RouteOption[]>([]);
  const [selectedRouteId, setSelectedRouteId] = useState<string | null>(null);
  const [isLoadingRoutes, setIsLoadingRoutes] = useState(false);
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [wasSaved, setWasSaved] = useState(false);

  const createRouteMutation = useMutation({
    mutationFn: (payload: CreateRoutePayload) => createRoute(token ?? "", payload),
  });

  useEffect(() => {
    selectionTargetRef.current = selectionTarget;
  }, [selectionTarget]);

  useEffect(() => {
    let mounted = true;
    let clickListener: google.maps.MapsEventListener | null = null;

    async function setupMap() {
      if (!mapContainerRef.current || mapRef.current) return;
      if (!googleMapsApiKey) {
        setMapError("أضف NEXT_PUBLIC_GOOGLE_MAPS_API_KEY حتى تظهر الخريطة.");
        return;
      }

      try {
        const maps = await loadGoogleMaps(googleMapsApiKey);
        if (!mounted || !mapContainerRef.current) return;

        mapRef.current = new maps.Map(mapContainerRef.current, {
          center: baghdadCenter,
          zoom: 12,
          mapTypeId: maps.MapTypeId.ROADMAP,
          fullscreenControl: false,
          mapTypeControl: false,
          streetViewControl: false,
          clickableIcons: false,
          gestureHandling: "greedy",
        });
        clickListener = mapRef.current.addListener(
          "click",
          (event: google.maps.MapMouseEvent) => {
            if (!event.latLng) return;
            setEndpoint(selectionTargetRef.current, {
              lat: event.latLng.lat(),
              lng: event.latLng.lng(),
            });
          },
        );
        setMapReady(true);
      } catch {
        if (mounted) setMapError("تعذر تحميل Google Maps.");
      }
    }

    void setupMap();

    return () => {
      mounted = false;
      clickListener?.remove();
      clearMapObjects();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    clearMapObjects();

    if (routeOptions.length > 0) {
      routeOptions.forEach((option, index) => {
        polylineRefs.current.push(
          drawRouteOption(map, option, index, option.id === selectedRouteId),
        );
      });
    } else if (routePath.length >= 2) {
      polylineRefs.current.push(
        buildPolyline(map, routePath, {
          color: "#1b5e8b",
          opacity: 0.92,
          weight: 5,
          zIndex: 4,
          withArrows: true,
        }),
      );
    }

    const endpoints = [
      originPoint ? { target: "origin" as const, point: originPoint } : null,
      destinationPoint
        ? { target: "destination" as const, point: destinationPoint }
        : null,
    ].filter(
      (
        endpoint,
      ): endpoint is { target: EndpointTarget; point: RoutePathPoint } =>
        Boolean(endpoint),
    );

    endpoints.forEach(({ target, point }) => {
      const marker = new google.maps.Marker({
        map,
        position: point,
        draggable: true,
        label: endpointLabel(target),
        title: target === "origin" ? "بداية الخط" : "نهاية الخط",
        zIndex: target === "origin" ? 40 : 41,
      });
      marker.addListener("dragend", (event: google.maps.MapMouseEvent) => {
        if (!event.latLng) return;
        setEndpoint(target, {
          lat: event.latLng.lat(),
          lng: event.latLng.lng(),
        });
      });
      markerRefs.current.push(marker);
    });
  }, [
    destinationPoint,
    mapReady,
    originPoint,
    routeOptions,
    routePath,
    selectedRouteId,
  ]);

  function updateField<K extends keyof RouteFormState>(
    key: K,
    value: RouteFormState[K],
  ) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function setEndpoint(target: EndpointTarget, point: RoutePathPoint) {
    if (target === "origin") {
      setOriginPoint(point);
      setSelectionTarget("destination");
    } else {
      setDestinationPoint(point);
    }
    setRoutePath([]);
    setRouteOptions([]);
    setSelectedRouteId(null);
    setFormError(null);
    setWasSaved(false);
  }

  async function loadRouteOptions() {
    if (!originPoint || !destinationPoint) {
      setFormError("حدد نقطة من ونقطة إلى أولاً.");
      return;
    }

    setIsLoadingRoutes(true);
    setFormError(null);

    try {
      const directions = new google.maps.DirectionsService();
      const result = await requestAvailableRoutes(
        directions,
        originPoint,
        destinationPoint,
      );
      const options = result.routes
        .map((route, index) => routeToOption(route, index))
        .filter((option): option is RouteOption => Boolean(option));

      if (options.length === 0) {
        setFormError("ماكو مسارات متاحة بين النقطتين.");
        setRouteOptions([]);
        setRoutePath([]);
        setSelectedRouteId(null);
        return;
      }

      setRouteOptions(options);
      selectRouteOption(options[0]);
      fitPoints(options.flatMap((option) => option.points));
    } catch {
      setFormError(
        "تعذر جلب المسارات. تأكد من تفعيل Directions API لنفس مفتاح Google.",
      );
    } finally {
      setIsLoadingRoutes(false);
    }
  }

  function selectRouteOption(option: RouteOption) {
    setSelectedRouteId(option.id);
    setRoutePath(option.points);
    setFormError(null);
    setWasSaved(false);
  }

  function clearPath() {
    setOriginPoint(null);
    setDestinationPoint(null);
    setRoutePath([]);
    setRouteOptions([]);
    setSelectedRouteId(null);
    setSelectionTarget("origin");
  }

  function fitPath() {
    fitPoints(routePath.length > 0 ? routePath : endpointPoints());
  }

  function fitPoints(points: RoutePathPoint[]) {
    const map = mapRef.current;
    if (!map || points.length === 0) return;
    const bounds = new google.maps.LatLngBounds();
    points.forEach((point) => bounds.extend(point));
    map.fitBounds(bounds, 72);
  }

  function endpointPoints() {
    return [originPoint, destinationPoint].filter(
      (point): point is RoutePathPoint => Boolean(point),
    );
  }

  function clearMapObjects() {
    markerRefs.current.forEach((marker) => marker.setMap(null));
    markerRefs.current = [];
    polylineRefs.current.forEach((polyline) => polyline.setMap(null));
    polylineRefs.current = [];
  }

  function buildPayload(): CreateRoutePayload {
    const firstPoint = originPoint ?? routePath[0];
    const lastPoint = destinationPoint ?? routePath[routePath.length - 1];
    const nameAr = form.nameAr.trim();
    const nameEn = form.nameEn.trim();

    return {
      nameAr,
      nameEn,
      routeType: form.routeType,
      status: form.status,
      fareMin: Number(form.fareMin),
      fareMax: Number(form.fareMax),
      operatingHoursStart: form.operatingHoursStart,
      operatingHoursEnd: form.operatingHoursEnd,
      confidenceScore: 90,
      routePath,
      stops: [
        {
          nameAr: `${nameAr} - بداية`,
          nameEn: `${nameEn} Start`,
          lat: firstPoint.lat,
          lng: firstPoint.lng,
          isMajor: true,
        },
        {
          nameAr: `${nameAr} - نهاية`,
          nameEn: `${nameEn} End`,
          lat: lastPoint.lat,
          lng: lastPoint.lng,
          isMajor: true,
        },
      ],
    };
  }

  function resetBuilder() {
    setForm(initialFormState);
    setOriginPoint(null);
    setDestinationPoint(null);
    setRoutePath([]);
    setRouteOptions([]);
    setSelectedRouteId(null);
    setSelectionTarget("origin");
    setIsLoadingRoutes(false);
    setFormError(null);
    setWasSaved(false);
    createRouteMutation.reset();
  }

  function buildDemoRoute(payload: CreateRoutePayload): TransitRoute {
    const now = new Date().toISOString();
    return {
      id: `route-local-${Date.now()}`,
      nameAr: payload.nameAr,
      nameEn: payload.nameEn,
      routeType: payload.routeType,
      status: payload.status ?? "unverified",
      fareMin: payload.fareMin,
      fareMax: payload.fareMax,
      operatingHoursStart: payload.operatingHoursStart,
      operatingHoursEnd: payload.operatingHoursEnd,
      confidenceScore: payload.confidenceScore ?? 90,
      lastVerifiedAt: now,
      routePath: payload.routePath ?? null,
      createdAt: now,
      updatedAt: now,
    };
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!form.nameAr.trim() || !form.nameEn.trim()) {
      setFormError("اكتب اسم الخط بالعربي والإنكليزي.");
      return;
    }

    if (!originPoint || !destinationPoint) {
      setFormError("حدد نقطة من ونقطة إلى على الخريطة.");
      return;
    }

    if (routePath.length < 2) {
      setFormError("اضغط جلب المسارات واختار مسار قبل الحفظ.");
      return;
    }

    const payload = buildPayload();
    if (isDemo || !token) {
      onCreated(buildDemoRoute(payload));
      setWasSaved(true);
      resetBuilder();
      return;
    }

    createRouteMutation.mutate(payload, {
      onSuccess: (route) => {
        onCreated(route);
        setWasSaved(true);
        resetBuilder();
      },
      onError: (error) => {
        setFormError(
          error instanceof Error ? error.message : "تعذر حفظ الخط الجديد.",
        );
      },
    });
  }

  return (
    <section className="panel route-builder-panel" aria-label="إضافة خط">
      <div className="panel-head">
        <div>
          <h3>إضافة خط</h3>
          <span>{routePath.length.toLocaleString("ar-IQ")} نقطة مسار</span>
        </div>
        <button
          className="icon-button"
          type="button"
          title="إغلاق"
          onClick={onCancel}
        >
          <X aria-hidden="true" size={18} />
        </button>
      </div>

      {(formError || createRouteMutation.isError) && (
        <div className="inline-alert">
          <AlertCircle aria-hidden="true" size={18} />
          <span>{formError ?? "تعذر حفظ الخط الجديد."}</span>
        </div>
      )}

      {createRouteMutation.isSuccess || wasSaved ? (
        <div className="inline-success">
          <Check aria-hidden="true" size={18} />
          <span>تم حفظ الخط.</span>
        </div>
      ) : null}

      <form className="route-builder-grid" onSubmit={handleSubmit}>
        <div className="route-builder-form">
          <label className="field compact-field">
            <span>اسم الخط عربي</span>
            <input
              value={form.nameAr}
              onChange={(event) => updateField("nameAr", event.target.value)}
              placeholder="مثال: الباب الشرقي - الكرادة"
            />
          </label>

          <label className="field compact-field">
            <span>اسم الخط English</span>
            <input
              value={form.nameEn}
              onChange={(event) => updateField("nameEn", event.target.value)}
              placeholder="Bab Al-Sharqi - Karrada"
              dir="ltr"
            />
          </label>

          <label className="field compact-field">
            <span>النوع</span>
            <select
              value={form.routeType}
              onChange={(event) =>
                updateField("routeType", event.target.value as RouteType)
              }
            >
              <option value="kia">كية</option>
              <option value="coaster">كوستر</option>
              <option value="bus">باص</option>
              <option value="minibus">ميني باص</option>
            </select>
          </label>

          <label className="field compact-field">
            <span>الحالة</span>
            <select
              value={form.status}
              onChange={(event) =>
                updateField("status", event.target.value as RouteStatus)
              }
            >
              <option value="active">نشط</option>
              <option value="unverified">غير موثق</option>
              <option value="inactive">متوقف</option>
            </select>
          </label>

          <label className="field compact-field">
            <span>أقل أجرة</span>
            <input
              inputMode="numeric"
              value={form.fareMin}
              onChange={(event) => updateField("fareMin", event.target.value)}
            />
          </label>

          <label className="field compact-field">
            <span>أعلى أجرة</span>
            <input
              inputMode="numeric"
              value={form.fareMax}
              onChange={(event) => updateField("fareMax", event.target.value)}
            />
          </label>

          <label className="field compact-field">
            <span>بداية الدوام</span>
            <input
              type="time"
              value={form.operatingHoursStart}
              onChange={(event) =>
                updateField("operatingHoursStart", event.target.value)
              }
            />
          </label>

          <label className="field compact-field">
            <span>نهاية الدوام</span>
            <input
              type="time"
              value={form.operatingHoursEnd}
              onChange={(event) =>
                updateField("operatingHoursEnd", event.target.value)
              }
            />
          </label>

          <div className="route-endpoint-box">
            <div className="endpoint-toggle">
              <button
                className={selectionTarget === "origin" ? "active" : ""}
                type="button"
                onClick={() => setSelectionTarget("origin")}
              >
                من
              </button>
              <button
                className={selectionTarget === "destination" ? "active" : ""}
                type="button"
                onClick={() => setSelectionTarget("destination")}
              >
                إلى
              </button>
            </div>
            <div className="endpoint-status">
              <span>{originPoint ? "تم تحديد من" : "حدد من على الخريطة"}</span>
              <span>
                {destinationPoint ? "تم تحديد إلى" : "حدد إلى على الخريطة"}
              </span>
            </div>
            <button
              className="primary-button compact-button"
              type="button"
              disabled={!originPoint || !destinationPoint || isLoadingRoutes}
              onClick={loadRouteOptions}
            >
              <RouteIcon aria-hidden="true" size={16} />
              <span>{isLoadingRoutes ? "جلب المسارات" : "جلب المسارات"}</span>
            </button>
          </div>

          {routeOptions.length > 0 ? (
            <div className="route-options-list">
              {routeOptions.map((option, index) => (
                <button
                  className={
                    option.id === selectedRouteId
                      ? "route-option-row active"
                      : "route-option-row"
                  }
                  key={option.id}
                  type="button"
                  onClick={() => selectRouteOption(option)}
                >
                  <strong>{option.summary || `مسار ${index + 1}`}</strong>
                  <span>
                    {option.distanceText} · {option.durationText} ·{" "}
                    {option.points.length.toLocaleString("ar-IQ")} نقطة
                  </span>
                </button>
              ))}
            </div>
          ) : null}

          <div className="builder-actions">
            <button
              className="primary-button compact-button"
              type="submit"
              disabled={createRouteMutation.isPending}
            >
              <Save aria-hidden="true" size={16} />
              <span>{createRouteMutation.isPending ? "حفظ" : "حفظ الخط"}</span>
            </button>
            <button
              className="ghost-button compact-button"
              type="button"
              onClick={resetBuilder}
            >
              <RotateCcw aria-hidden="true" size={16} />
              <span>إعادة</span>
            </button>
          </div>
        </div>

        <div className="route-map-editor">
          <div ref={mapContainerRef} className="route-builder-map" />
          {mapError ? <div className="map-loading">{mapError}</div> : null}
          {!mapReady && !mapError ? (
            <div className="map-loading">تحميل الخريطة</div>
          ) : null}
          <div className="route-editor-toolbar">
            <span>
              <MapPinned aria-hidden="true" size={15} />
              {routeOptions.length > 0
                ? `${routeOptions.length.toLocaleString("ar-IQ")} مسارات`
                : `${routePath.length.toLocaleString("ar-IQ")} نقطة`}
            </span>
            <button
              type="button"
              onClick={fitPath}
              disabled={routePath.length < 2 && endpointPoints().length === 0}
            >
              توسيط
            </button>
            <button
              type="button"
              onClick={clearPath}
              disabled={
                routePath.length === 0 && !originPoint && !destinationPoint
              }
            >
              <Trash2 aria-hidden="true" size={15} />
            </button>
          </div>
        </div>
      </form>
    </section>
  );
}

function requestAvailableRoutes(
  directions: google.maps.DirectionsService,
  origin: RoutePathPoint,
  destination: RoutePathPoint,
) {
  return new Promise<google.maps.DirectionsResult>((resolve, reject) => {
    directions.route(
      {
        origin,
        destination,
        provideRouteAlternatives: true,
        travelMode: google.maps.TravelMode.DRIVING,
      },
      (result, status) => {
        if (status !== google.maps.DirectionsStatus.OK || !result) {
          reject(new Error(status));
          return;
        }

        resolve(result);
      },
    );
  });
}

function routeToOption(
  route: google.maps.DirectionsRoute,
  index: number,
): RouteOption | null {
  const points = extractRoutePoints(route);
  if (points.length < 2) return null;

  const distanceMeters = route.legs.reduce(
    (total, leg) => total + (leg.distance?.value ?? 0),
    0,
  );
  const durationSeconds = route.legs.reduce(
    (total, leg) => total + (leg.duration?.value ?? 0),
    0,
  );

  return {
    id: `option-${index}`,
    summary: route.summary || `مسار ${index + 1}`,
    distanceText: formatDistance(distanceMeters),
    durationText: formatDuration(durationSeconds),
    points,
  };
}

function extractRoutePoints(route: google.maps.DirectionsRoute) {
  const detailedPath = route.legs.flatMap((leg) =>
    leg.steps.flatMap((step) => step.path.map(latLngToPoint)),
  );
  if (detailedPath.length >= 2) return detailedPath;
  return route.overview_path.map(latLngToPoint);
}

function drawRouteOption(
  map: google.maps.Map,
  option: RouteOption,
  index: number,
  isSelected: boolean,
) {
  const color = isSelected ? "#1b5e8b" : routeOptionColors[index % routeOptionColors.length];
  return buildPolyline(map, option.points, {
    color,
    opacity: isSelected ? 0.94 : 0.38,
    weight: isSelected ? 6 : 4,
    zIndex: isSelected ? 8 : 2,
    withArrows: isSelected,
  });
}

const routeOptionColors = ["#64748b", "#b45309", "#6d28d9", "#15803d"];

function buildPolyline(
  map: google.maps.Map,
  path: RoutePathPoint[],
  options: {
    color: string;
    opacity: number;
    weight: number;
    zIndex: number;
    withArrows: boolean;
  },
) {
  const polyline = new google.maps.Polyline({
    map,
    path,
    strokeColor: options.color,
    strokeOpacity: options.opacity,
    strokeWeight: options.weight,
    zIndex: options.zIndex,
    icons: options.withArrows
      ? [
          {
            icon: {
              path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
              scale: 3,
              strokeColor: options.color,
              fillColor: options.color,
              fillOpacity: 1,
            },
            offset: "50%",
            repeat: "170px",
          },
        ]
      : undefined,
  });
  return polyline;
}

function latLngToPoint(latLng: google.maps.LatLng) {
  return { lat: latLng.lat(), lng: latLng.lng() };
}

function endpointLabel(target: EndpointTarget): google.maps.MarkerLabel {
  const text = target === "origin" ? "من" : "إلى";
  return {
    text,
    color: "#ffffff",
    fontSize: "12px",
    fontWeight: "900",
  };
}

function formatDistance(value: number) {
  if (value <= 0) return "غير معروف";
  if (value < 1000) return `${Math.round(value).toLocaleString("ar-IQ")} م`;
  return `${(value / 1000).toFixed(1)} كم`;
}

function formatDuration(value: number) {
  if (value <= 0) return "وقت غير معروف";
  const minutes = Math.max(1, Math.round(value / 60));
  return `${minutes.toLocaleString("ar-IQ")} دقيقة`;
}
