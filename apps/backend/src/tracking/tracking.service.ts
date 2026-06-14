import { Injectable, NotFoundException } from "@nestjs/common";
import { InjectRepository } from "@nestjs/typeorm";
import { Repository } from "typeorm";
import { PassengerWaitStatus } from "../common/enums/transit.enums";
import { TransitRoute } from "../routes/route.entity";
import { Stop } from "../stops/stop.entity";
import { PassengerWait } from "./passenger-wait.entity";
import {
  RouteArrivalQueryDto,
  StartPassengerWaitDto,
  UpdatePassengerWaitDto,
} from "./tracking.dto";
import { Vehicle } from "./vehicle.entity";

export interface VehicleLocationPayload {
  vehicleId: string;
  lat: number;
  lng: number;
  speedMetersPerSecond?: number;
}

@Injectable()
export class TrackingService {
  constructor(
    @InjectRepository(Vehicle) private readonly vehicles: Repository<Vehicle>,
    @InjectRepository(TransitRoute)
    private readonly routes: Repository<TransitRoute>,
    @InjectRepository(PassengerWait)
    private readonly passengerWaits: Repository<PassengerWait>,
  ) {}

  async updateVehicleLocation(payload: VehicleLocationPayload) {
    const vehicle = await this.vehicles.findOne({
      where: { id: payload.vehicleId },
    });
    if (!vehicle) throw new NotFoundException("Vehicle not found");
    vehicle.lastLocation = {
      type: "Point",
      coordinates: [payload.lng, payload.lat],
    };
    if (
      payload.speedMetersPerSecond !== undefined &&
      payload.speedMetersPerSecond >= 0
    ) {
      vehicle.speedMetersPerSecond = payload.speedMetersPerSecond;
    }
    vehicle.lastSeenAt = new Date();
    vehicle.isTrackingActive = true;
    return this.vehicles.save(vehicle);
  }

  async getRouteArrival(routeId: string, query: RouteArrivalQueryDto) {
    const route = await this.routes.findOne({
      where: { id: routeId },
      relations: { routeStops: true },
      order: { routeStops: { stopSequence: "ASC" } },
    });
    if (!route) throw new NotFoundException("Route not found");

    const orderedStops = [...route.routeStops].sort(
      (a, b) => a.stopSequence - b.stopSequence,
    );
    if (orderedStops.length === 0)
      throw new NotFoundException("Route has no path anchors");

    const explicitPickupAnchor = orderedStops.find(
      (routeStop) => routeStop.stopId === query.pickupStopId,
    );
    const pickupLat =
      explicitPickupAnchor?.stop.location.coordinates[1] ??
      query.lat ??
      orderedStops[0].stop.location.coordinates[1];
    const pickupLng =
      explicitPickupAnchor?.stop.location.coordinates[0] ??
      query.lng ??
      orderedStops[0].stop.location.coordinates[0];
    const pickupProgressMeters = this.progressAlongRouteMeters(
      orderedStops,
      pickupLat,
      pickupLng,
    );
    const nearestPickupAnchor =
      this.nearestRouteStop(orderedStops, pickupLat, pickupLng) ??
      orderedStops[0];

    const activeVehicles = await this.vehicles.find({
      where: { routeId, isTrackingActive: true },
    });

    const candidates = activeVehicles
      .filter((vehicle) => vehicle.lastLocation)
      .map((vehicle) => {
        const vehiclePoint = vehicle.lastLocation!.coordinates;
        const nearestStop = this.nearestRouteStop(
          orderedStops,
          vehiclePoint[1],
          vehiclePoint[0],
        );
        const vehicleProgressMeters = this.progressAlongRouteMeters(
          orderedStops,
          vehiclePoint[1],
          vehiclePoint[0],
        );
        const remainingOnRouteMeters =
          pickupProgressMeters - vehicleProgressMeters;
        const hasPassedPickup = remainingOnRouteMeters < -50;
        const distanceMeters = Math.max(
          0,
          Math.round(
            hasPassedPickup
              ? this.distanceMeters(
                  vehiclePoint[1],
                  vehiclePoint[0],
                  pickupLat,
                  pickupLng,
                )
              : remainingOnRouteMeters,
          ),
        );
        const etaMinutes = this.etaMinutes(
          distanceMeters,
          vehicle.speedMetersPerSecond,
        );
        return {
          vehicleId: vehicle.id,
          plateNumber: vehicle.plateNumber,
          lat: vehiclePoint[1],
          lng: vehiclePoint[0],
          distanceMeters,
          etaMinutes,
          speedMetersPerSecond: vehicle.speedMetersPerSecond,
          lastSeenAt: vehicle.lastSeenAt,
          hasPassedPickup,
          nearestStop: nearestStop
            ? {
                id: nearestStop.stop.id,
                nameAr: nearestStop.stop.nameAr,
                sequence: nearestStop.stopSequence,
              }
            : null,
        };
      })
      .sort((a, b) => a.distanceMeters - b.distanceMeters);

    const upcoming = candidates.filter(
      (candidate) => !candidate.hasPassedPickup,
    );
    const selectedVehicle = upcoming[0] ?? null;
    const nextCycleVehicle = selectedVehicle ? null : (candidates[0] ?? null);

    return {
      routeId,
      pickupPoint: {
        lat: pickupLat,
        lng: pickupLng,
        progressMeters: Math.round(pickupProgressMeters),
        nearestLandmark: {
          id: nearestPickupAnchor.stop.id,
          nameAr: nearestPickupAnchor.stop.nameAr,
          landmarkAr: nearestPickupAnchor.stop.landmarkAr,
          sequence: nearestPickupAnchor.stopSequence,
        },
      },
      selectedVehicle,
      nextCycleVehicle,
      skippedPassedVehicles: candidates
        .filter((candidate) => candidate.hasPassedPickup)
        .slice(0, 3),
      alternatives: upcoming.slice(1, 4),
      message: selectedVehicle
        ? "هذه أقرب كية بعدها ما وصلت لمكان صعودك على نفس اتجاه الخط"
        : nextCycleVehicle
          ? "الكيات الظاهرة عدّت مكان صعودك، ننتظر كية بعدها على نفس الاتجاه"
          : "ماكو تتبع حي حالياً لهذا الخط",
    };
  }

  async startPassengerWait(routeId: string, dto: StartPassengerWaitDto) {
    const route = await this.routeWithStops(routeId);
    const orderedStops = this.orderedRouteStops(route);
    const progressMeters = this.progressAlongRouteMeters(
      orderedStops,
      dto.lat,
      dto.lng,
    );

    await this.passengerWaits.update(
      {
        routeId,
        anonymousSessionId: dto.anonymousSessionId,
        status: PassengerWaitStatus.Waiting,
      },
      { status: PassengerWaitStatus.Cancelled },
    );

    return this.passengerWaits.save(
      this.passengerWaits.create({
        routeId,
        anonymousSessionId: dto.anonymousSessionId,
        pickupLocation: { type: "Point", coordinates: [dto.lng, dto.lat] },
        lastLocation: { type: "Point", coordinates: [dto.lng, dto.lat] },
        pickupProgressMeters: progressMeters,
        lastProgressMeters: progressMeters,
        status: PassengerWaitStatus.Waiting,
      }),
    );
  }

  async updatePassengerWaitLocation(
    waitId: string,
    dto: UpdatePassengerWaitDto,
  ) {
    const wait = await this.passengerWaits.findOne({ where: { id: waitId } });
    if (!wait) throw new NotFoundException("Passenger wait not found");
    if (wait.status !== PassengerWaitStatus.Waiting) return wait;

    const route = await this.routeWithStops(wait.routeId);
    const orderedStops = this.orderedRouteStops(route);
    const progressMeters = this.progressAlongRouteMeters(
      orderedStops,
      dto.lat,
      dto.lng,
    );
    const distanceToRouteMeters = this.distanceToRouteMeters(
      orderedStops,
      dto.lat,
      dto.lng,
    );
    const forwardProgressMeters = progressMeters - wait.pickupProgressMeters;
    const lastPoint = wait.lastLocation.coordinates;
    const progressSinceLastMeters = progressMeters - wait.lastProgressMeters;
    const displacementSinceLastMeters = this.distanceMeters(
      dto.lat,
      dto.lng,
      lastPoint[1],
      lastPoint[0],
    );
    const hasReliableAccuracy =
      dto.accuracyMeters === undefined || dto.accuracyMeters <= 85;
    const isOnRoute = distanceToRouteMeters <= 260;
    const isClearBoardingMovement =
      forwardProgressMeters >= 120 && isOnRoute && hasReliableAccuracy;
    const isMovingForwardOnRoute =
      forwardProgressMeters >= 70 &&
      progressSinceLastMeters >= 35 &&
      displacementSinceLastMeters >= 30 &&
      isOnRoute &&
      hasReliableAccuracy;
    const isFastForwardOnRoute =
      forwardProgressMeters >= 60 &&
      progressSinceLastMeters >= 25 &&
      (dto.speedMetersPerSecond ?? 0) >= 1.6 &&
      isOnRoute &&
      hasReliableAccuracy;

    wait.lastLocation = { type: "Point", coordinates: [dto.lng, dto.lat] };
    wait.lastProgressMeters = progressMeters;

    if (
      isClearBoardingMovement ||
      isMovingForwardOnRoute ||
      isFastForwardOnRoute
    ) {
      wait.status = PassengerWaitStatus.Boarded;
      wait.boardedAt = new Date();
    }

    return this.passengerWaits.save(wait);
  }

  async cancelPassengerWait(waitId: string) {
    const wait = await this.passengerWaits.findOne({ where: { id: waitId } });
    if (!wait) throw new NotFoundException("Passenger wait not found");
    if (wait.status === PassengerWaitStatus.Waiting) {
      wait.status = PassengerWaitStatus.Cancelled;
    }
    return this.passengerWaits.save(wait);
  }

  async getActivePassengerWaits(routeId: string) {
    const waits = await this.passengerWaits.find({
      where: { routeId, status: PassengerWaitStatus.Waiting },
      order: { createdAt: "DESC" },
    });
    return waits.map((wait) => ({
      id: wait.id,
      routeId: wait.routeId,
      lat: wait.lastLocation.coordinates[1],
      lng: wait.lastLocation.coordinates[0],
      status: wait.status,
      createdAt: wait.createdAt,
      updatedAt: wait.updatedAt,
    }));
  }

  private async routeWithStops(routeId: string) {
    const route = await this.routes.findOne({
      where: { id: routeId },
      relations: { routeStops: true },
      order: { routeStops: { stopSequence: "ASC" } },
    });
    if (!route) throw new NotFoundException("Route not found");
    return route;
  }

  private orderedRouteStops(route: TransitRoute) {
    return [...route.routeStops].sort(
      (a, b) => a.stopSequence - b.stopSequence,
    );
  }

  private nearestRouteStop(
    routeStops: { stop: Stop; stopSequence: number }[],
    lat?: number,
    lng?: number,
  ) {
    if (lat === undefined || lng === undefined) return null;
    return routeStops
      .map((routeStop) => ({
        routeStop,
        distance: this.distanceMeters(
          lat,
          lng,
          routeStop.stop.location.coordinates[1],
          routeStop.stop.location.coordinates[0],
        ),
      }))
      .sort((a, b) => a.distance - b.distance)[0]?.routeStop;
  }

  private distanceMeters(
    lat1: number,
    lng1: number,
    lat2: number,
    lng2: number,
  ) {
    const earthRadius = 6371000;
    const toRad = (value: number) => (value * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) *
        Math.cos(toRad(lat2)) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  private etaMinutes(
    distanceMeters: number,
    speedMetersPerSecond?: number | null,
  ) {
    const effectiveSpeed =
      speedMetersPerSecond && speedMetersPerSecond >= 2.5
        ? Math.min(speedMetersPerSecond, 13)
        : 6.1;
    return Math.max(1, Math.round(distanceMeters / (effectiveSpeed * 60)));
  }

  private progressAlongRouteMeters(
    routeStops: { stop: Stop }[],
    lat: number,
    lng: number,
  ) {
    let bestProgress = 0;
    let bestDistance = Number.POSITIVE_INFINITY;
    let accumulated = 0;

    for (let index = 0; index < routeStops.length - 1; index += 1) {
      const start = routeStops[index].stop.location.coordinates;
      const end = routeStops[index + 1].stop.location.coordinates;
      const segmentMeters = this.distanceMeters(
        start[1],
        start[0],
        end[1],
        end[0],
      );
      const projected = this.projectToSegment(
        lat,
        lng,
        start[1],
        start[0],
        end[1],
        end[0],
      );
      const distanceToSegment = this.distanceMeters(
        lat,
        lng,
        projected.lat,
        projected.lng,
      );
      if (distanceToSegment < bestDistance) {
        bestDistance = distanceToSegment;
        bestProgress = accumulated + segmentMeters * projected.t;
      }
      accumulated += segmentMeters;
    }

    return bestProgress;
  }

  private distanceToRouteMeters(
    routeStops: { stop: Stop }[],
    lat: number,
    lng: number,
  ) {
    let bestDistance = Number.POSITIVE_INFINITY;
    for (let index = 0; index < routeStops.length - 1; index += 1) {
      const start = routeStops[index].stop.location.coordinates;
      const end = routeStops[index + 1].stop.location.coordinates;
      const projected = this.projectToSegment(
        lat,
        lng,
        start[1],
        start[0],
        end[1],
        end[0],
      );
      bestDistance = Math.min(
        bestDistance,
        this.distanceMeters(lat, lng, projected.lat, projected.lng),
      );
    }
    return bestDistance;
  }

  private projectToSegment(
    lat: number,
    lng: number,
    startLat: number,
    startLng: number,
    endLat: number,
    endLng: number,
  ) {
    const x = lng;
    const y = lat;
    const x1 = startLng;
    const y1 = startLat;
    const x2 = endLng;
    const y2 = endLat;
    const dx = x2 - x1;
    const dy = y2 - y1;
    const lengthSquared = dx * dx + dy * dy;
    const rawT =
      lengthSquared === 0 ? 0 : ((x - x1) * dx + (y - y1) * dy) / lengthSquared;
    const t = Math.max(0, Math.min(1, rawT));
    return { lat: y1 + dy * t, lng: x1 + dx * t, t };
  }
}
