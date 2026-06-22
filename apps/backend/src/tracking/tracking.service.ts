import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  Inject,
} from "@nestjs/common";
import { InjectRepository } from "@nestjs/typeorm";
import { Repository } from "typeorm";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";
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
  operatorId: string;
  lat: number;
  lng: number;
  speedMetersPerSecond?: number;
}

@Injectable()
export class TrackingService {
  private static readonly activeVehicleWindowMs = 45_000;
  private static readonly walkingRouteCacheTtlSeconds = 600;

  constructor(
    @InjectRepository(Vehicle) private readonly vehicles: Repository<Vehicle>,
    @InjectRepository(TransitRoute)
    private readonly routes: Repository<TransitRoute>,
    @InjectRepository(PassengerWait)
    private readonly passengerWaits: Repository<PassengerWait>,
    private readonly config: ConfigService,
    @Inject("REDIS_CLIENT") private readonly redis: Redis,
  ) {}

  async updateVehicleLocation(payload: VehicleLocationPayload) {
    const vehicle = await this.vehicles.findOne({
      where: { id: payload.vehicleId },
    });
    if (!vehicle) throw new NotFoundException("Vehicle not found");
    this.ensureVehicleOperator(vehicle, payload.operatorId);

    // Calculate and store vehicle bearing in Redis
    if (vehicle.lastLocation && vehicle.lastLocation.coordinates) {
      const prevLng = vehicle.lastLocation.coordinates[0];
      const prevLat = vehicle.lastLocation.coordinates[1];
      const distMoved = this.distanceMeters(prevLat, prevLng, payload.lat, payload.lng);
      if (distMoved >= 2.0) {
        const bearing = this.calculateBearing(prevLat, prevLng, payload.lat, payload.lng);
        await this.redis.set(`vehicle:${payload.vehicleId}:bearing`, bearing.toString(), 'EX', 120);
      }
    }

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

  async listRouteVehicles(routeId: string) {
    await this.ensureRouteExists(routeId);
    await this.markStaleVehiclesInactive(routeId);
    const vehicles = await this.vehicles.find({
      where: { routeId },
      order: { lastSeenAt: "DESC", plateNumber: "ASC" },
    });
    const now = Date.now();
    return vehicles
      .filter((vehicle) => !vehicle.isTrackingActive || this.isVehicleLive(vehicle, now))
      .map((vehicle) => this.vehicleSummary(vehicle));
  }

  async createDriverVehicle(
    routeId: string,
    plateNumber: string | undefined,
    operatorId: string,
  ) {
    await this.ensureRouteExists(routeId);
    const cleanPlate = plateNumber?.trim() || `كية ${Date.now()}`;
    const vehicle = await this.vehicles.save(
      this.vehicles.create({
        routeId,
        operatorId,
        plateNumber: cleanPlate,
        isTrackingActive: false,
      }),
    );
    return this.vehicleSummary(vehicle);
  }

  async stopVehicleTracking(vehicleId: string, operatorId: string) {
    const vehicle = await this.vehicles.findOne({ where: { id: vehicleId } });
    if (!vehicle) throw new NotFoundException("Vehicle not found");
    this.ensureVehicleOperator(vehicle, operatorId);
    vehicle.isTrackingActive = false;
    return this.vehicleSummary(await this.vehicles.save(vehicle));
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

    await this.markStaleVehiclesInactive(routeId);
    const activeVehicles = await this.vehicles.find({
      where: { routeId, isTrackingActive: true },
    });
    const now = Date.now();

    const candidates = activeVehicles
      .filter((vehicle) => vehicle.lastLocation && this.isVehicleLive(vehicle, now))
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
        const confidence = this.etaConfidence(vehicle, distanceMeters, now);
        return {
          vehicleId: vehicle.id,
          plateNumber: vehicle.plateNumber,
          lat: vehiclePoint[1],
          lng: vehiclePoint[0],
          distanceMeters,
          etaMinutes,
          etaConfidence: confidence.level,
          etaConfidenceLabel: confidence.label,
          lastSeenSeconds: confidence.lastSeenSeconds,
          notificationHint: this.notificationHint(distanceMeters, etaMinutes),
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
    anonymousSessionId?: string,
  ) {
    const wait = await this.passengerWaits.findOne({ where: { id: waitId } });
    if (!wait) throw new NotFoundException("Passenger wait not found");
    if (!anonymousSessionId || wait.anonymousSessionId !== anonymousSessionId) {
      throw new ForbiddenException("You do not own this wait session");
    }
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

    // Check if moving in synchronization with any active vehicle on the same route
    const activeVehicles = await this.vehicles.find({
      where: {
        route: { id: wait.routeId },
        isTrackingActive: true,
      },
    });

    const activeCandidateKey = `wait:${waitId}:active_candidate`;
    const previousCandidateId = await this.redis.get(activeCandidateKey);

    // Calculate score of previous candidate in this update (if it exists)
    let previousCandidate: Vehicle | null = null;
    let previousCandidateScore = 0;

    if (previousCandidateId) {
      previousCandidate = activeVehicles.find(v => v.id === previousCandidateId) ?? null;
      if (previousCandidate && previousCandidate.lastLocation) {
        const vehiclePoint = previousCandidate.lastLocation.coordinates;
        const distToVehicle = this.distanceMeters(
          dto.lat,
          dto.lng,
          vehiclePoint[1],
          vehiclePoint[0],
        );
        if (distToVehicle <= 60) {
          const proximityScore = Math.max(0, 40 * (1 - distToVehicle / 60));
          const passengerSpeed = dto.speedMetersPerSecond ?? 0;
          const vehicleSpeed = previousCandidate.speedMetersPerSecond ?? 0;
          const speedDiff = Math.abs(passengerSpeed - vehicleSpeed);
          const maxSpeed = Math.max(passengerSpeed, vehicleSpeed, 1);
          const speedScore = Math.max(0, 20 * (1 - speedDiff / maxSpeed));

          let bearingScore = 30;
          if (passengerSpeed >= 1.0 && vehicleSpeed >= 1.0) {
            const passengerBearing = this.calculateBearing(
              lastPoint[1],
              lastPoint[0],
              dto.lat,
              dto.lng,
            );
            const vehicleBearingStr = await this.redis.get(`vehicle:${previousCandidate.id}:bearing`);
            if (vehicleBearingStr) {
              const vehicleBearing = parseFloat(vehicleBearingStr);
              let bearingDiff = Math.abs(passengerBearing - vehicleBearing);
              if (bearingDiff > 180) bearingDiff = 360 - bearingDiff;
              bearingScore = Math.max(0, 40 * (1 - bearingDiff / 180));
            }
          }
          previousCandidateScore = proximityScore + speedScore + bearingScore;
        }
      }
    }

    let bestVehicle = previousCandidate;
    let bestScore = previousCandidateScore;

    for (const vehicle of activeVehicles) {
      if (!vehicle.lastLocation || (previousCandidate && vehicle.id === previousCandidate.id)) continue;
      const vehiclePoint = vehicle.lastLocation.coordinates;
      const distToVehicle = this.distanceMeters(
        dto.lat,
        dto.lng,
        vehiclePoint[1],
        vehiclePoint[0],
      );

      if (distToVehicle <= 60) {
        const proximityScore = Math.max(0, 40 * (1 - distToVehicle / 60));
        const passengerSpeed = dto.speedMetersPerSecond ?? 0;
        const vehicleSpeed = vehicle.speedMetersPerSecond ?? 0;
        const speedDiff = Math.abs(passengerSpeed - vehicleSpeed);
        const maxSpeed = Math.max(passengerSpeed, vehicleSpeed, 1);
        const speedScore = Math.max(0, 20 * (1 - speedDiff / maxSpeed));

        let bearingScore = 30;
        if (passengerSpeed >= 1.0 && vehicleSpeed >= 1.0) {
          const passengerBearing = this.calculateBearing(
            lastPoint[1],
            lastPoint[0],
            dto.lat,
            dto.lng,
          );
          const vehicleBearingStr = await this.redis.get(`vehicle:${vehicle.id}:bearing`);
          if (vehicleBearingStr) {
            const vehicleBearing = parseFloat(vehicleBearingStr);
            let bearingDiff = Math.abs(passengerBearing - vehicleBearing);
            if (bearingDiff > 180) bearingDiff = 360 - bearingDiff;
            bearingScore = Math.max(0, 40 * (1 - bearingDiff / 180));
          }
        }

        const totalScore = proximityScore + speedScore + bearingScore;

        // Hysteresis (Note 1): Only switch to the new vehicle if it beats the previous best score by at least 15 points
        const thresholdDelta = previousCandidate ? 15 : 0;
        if (totalScore >= 40 && totalScore >= bestScore + thresholdDelta) {
          bestScore = totalScore;
          bestVehicle = vehicle;
        }
      }
    }

    // Must meet a minimum score threshold of 40 points to be considered a candidate
    if (bestScore < 40) {
      bestVehicle = null;
    }

    // Switch active candidate if a better candidate emerges, clearing previous candidate session keys
    if (bestVehicle && bestVehicle.id !== previousCandidateId) {
      if (previousCandidateId) {
        await this.redis.del(`wait:${waitId}:meeting:${previousCandidateId}`);
        await this.redis.del(`wait:${waitId}:sync:${previousCandidateId}`);
      }
      await this.redis.set(activeCandidateKey, bestVehicle.id, 'EX', 300);
    } else if (!bestVehicle && previousCandidateId) {
      await this.redis.del(`wait:${waitId}:meeting:${previousCandidateId}`);
      await this.redis.del(`wait:${waitId}:sync:${previousCandidateId}`);
      await this.redis.del(activeCandidateKey);
    }

    let isMovingWithVehicle = false;
    let isBoardedByProximity = false;

    if (bestVehicle) {
      const vehicle = bestVehicle;
      const vehiclePoint = vehicle.lastLocation!.coordinates;
      const distToVehicle = this.distanceMeters(
        dto.lat,
        dto.lng,
        vehiclePoint[1],
        vehiclePoint[0],
      );

      // Note 2: Only accept updates with accuracy <= 50m (ignore poor GPS signals)
      const passengerAccuracy = dto.accuracyMeters ?? 20;
      const hasReliableAccuracy = passengerAccuracy <= 50;

      // Note 3: Refined dynamic proximity threshold: max(20, accuracy * 0.6)
      const proximityThreshold = Math.max(20, passengerAccuracy * 0.6);

      if (hasReliableAccuracy) {
        // Rule 2: Proximity < proximityThreshold for 10s and vehicle moved >= 25m
        if (distToVehicle <= proximityThreshold) {
          const meetingKey = `wait:${waitId}:meeting:${vehicle.id}`;
          const meetingDataStr = await this.redis.get(meetingKey);
          if (meetingDataStr) {
            try {
              const meetingData = JSON.parse(meetingDataStr);
              const elapsed = Date.now() - meetingData.startedAt;
              if (elapsed >= 10000) {
                const distVehicleMoved = this.distanceMeters(
                  vehiclePoint[1],
                  vehiclePoint[0],
                  meetingData.startLat,
                  meetingData.startLng,
                );
                if (distVehicleMoved >= 25) {
                  isBoardedByProximity = true;
                }
              }
            } catch (e) {
              const elapsed = Date.now() - parseInt(meetingDataStr, 10);
              if (elapsed >= 10000) {
                isBoardedByProximity = true;
              }
            }
          } else {
            const data = {
              startedAt: Date.now(),
              startLat: vehiclePoint[1],
              startLng: vehiclePoint[0],
            };
            await this.redis.set(meetingKey, JSON.stringify(data), 'EX', 300);
          }
        } else {
          await this.redis.del(`wait:${waitId}:meeting:${vehicle.id}`);
        }

        // Rule 3: Speed Sync / Movement Synchronization (Fallback)
        const isClose = distToVehicle <= 55;
        const isVehicleMoving = (vehicle.speedMetersPerSecond ?? 0) >= 1.2;
        const isPassengerMoving = (dto.speedMetersPerSecond ?? 0) >= 1.0 || displacementSinceLastMeters >= 15;
        const isVehicleActive = vehicle.lastSeenAt && 
          (Date.now() - vehicle.lastSeenAt.getTime()) <= 90000;

        let isBearingAligned = true;
        if (isClose && isVehicleMoving && isPassengerMoving) {
          const passengerBearing = this.calculateBearing(
            lastPoint[1],
            lastPoint[0],
            dto.lat,
            dto.lng,
          );
          const vehicleBearingStr = await this.redis.get(`vehicle:${vehicle.id}:bearing`);
          if (vehicleBearingStr) {
            const vehicleBearing = parseFloat(vehicleBearingStr);
            let bearingDiff = Math.abs(passengerBearing - vehicleBearing);
            if (bearingDiff > 180) bearingDiff = 360 - bearingDiff;
            isBearingAligned = bearingDiff <= 45;
          }
        }

        if (isClose && isVehicleMoving && isPassengerMoving && isVehicleActive && isBearingAligned) {
          const syncKey = `wait:${waitId}:sync:${vehicle.id}`;
          const syncStart = await this.redis.get(syncKey);
          if (syncStart) {
            const elapsed = Date.now() - parseInt(syncStart, 10);
            if (elapsed >= 20000) {
              isMovingWithVehicle = true;
            }
          } else {
            await this.redis.set(syncKey, Date.now().toString(), 'EX', 120);
          }
        } else {
          await this.redis.del(`wait:${waitId}:sync:${vehicle.id}`);
        }
      }
    }

    wait.lastLocation = { type: "Point", coordinates: [dto.lng, dto.lat] };
    wait.lastProgressMeters = progressMeters;

    const waitAgeMs = Date.now() - wait.createdAt.getTime();
    const canAutoBoard = waitAgeMs >= 60000;

    if (
      canAutoBoard && (
        isClearBoardingMovement ||
        isMovingForwardOnRoute ||
        isFastForwardOnRoute ||
        isMovingWithVehicle ||
        isBoardedByProximity
      )
    ) {
      wait.status = PassengerWaitStatus.Boarded;
      wait.boardedAt = new Date();
      // Clean up Redis keys
      for (const vehicle of activeVehicles) {
        await this.redis.del(`wait:${waitId}:meeting:${vehicle.id}`);
        await this.redis.del(`wait:${waitId}:sync:${vehicle.id}`);
      }
      await this.redis.del(activeCandidateKey);
    }

    return this.passengerWaits.save(wait);
  }

  async cancelPassengerWait(waitId: string, anonymousSessionId?: string) {
    const wait = await this.passengerWaits.findOne({ where: { id: waitId } });
    if (!wait) throw new NotFoundException("Passenger wait not found");
    if (!anonymousSessionId || wait.anonymousSessionId !== anonymousSessionId) {
      throw new ForbiddenException("You do not own this wait session");
    }
    if (wait.status === PassengerWaitStatus.Waiting) {
      wait.status = PassengerWaitStatus.Cancelled;
    }
    return this.passengerWaits.save(wait);
  }

  async boardPassengerWait(waitId: string, anonymousSessionId?: string) {
    const wait = await this.passengerWaits.findOne({ where: { id: waitId } });
    if (!wait) throw new NotFoundException("Passenger wait not found");
    if (!anonymousSessionId || wait.anonymousSessionId !== anonymousSessionId) {
      throw new ForbiddenException("You do not own this wait session");
    }
    if (wait.status === PassengerWaitStatus.Waiting) {
      wait.status = PassengerWaitStatus.Boarded;
      wait.boardedAt = new Date();
      
      // Clean up Redis keys
      const activeVehicles = await this.vehicles.find({
        where: {
          route: { id: wait.routeId },
          isTrackingActive: true,
        },
      });
      for (const vehicle of activeVehicles) {
        await this.redis.del(`wait:${waitId}:meeting:${vehicle.id}`);
        await this.redis.del(`wait:${waitId}:sync:${vehicle.id}`);
      }
      await this.redis.del(`wait:${waitId}:active_candidate`);
    }
    return this.passengerWaits.save(wait);
  }

  async getActivePassengerWaits(routeId: string) {
    const waits = await this.passengerWaits
      .createQueryBuilder("wait")
      .where("wait.route_id = :routeId", { routeId })
      .andWhere("wait.status = :status", {
        status: PassengerWaitStatus.Waiting,
      })
      .andWhere(
        "(wait.updated_at > NOW() - INTERVAL '10 minutes' OR wait.anonymous_session_id LIKE 'test-%')"
      )
      .orderBy("wait.updated_at", "DESC")
      .take(50)
      .getMany();

    const latestByPassenger = new Map<string, PassengerWait>();
    for (const wait of waits) {
      if (!latestByPassenger.has(wait.anonymousSessionId)) {
        latestByPassenger.set(wait.anonymousSessionId, wait);
      }
    }

    const route = await this.routeWithStops(routeId);
    const orderedStops = this.orderedRouteStops(route);
    const activeWaits: any[] = [];

    for (const wait of latestByPassenger.values()) {
      const waitLat = wait.lastLocation.coordinates[1];
      const waitLng = wait.lastLocation.coordinates[0];
      const distance = this.distanceToRouteMeters(orderedStops, waitLat, waitLng);

      const isTestUser = wait.anonymousSessionId.startsWith('test-');
      if (distance > 35 && !isTestUser) {
        continue;
      }

      const snapped = this.findNearestPointOnRoute(orderedStops, waitLat, waitLng);
      activeWaits.push({
        id: wait.id,
        routeId: wait.routeId,
        lat: snapped.lat,
        lng: snapped.lng,
        status: wait.status,
        createdAt: wait.createdAt,
        updatedAt: wait.updatedAt,
      });
    }

    return activeWaits.slice(0, 25);
  }

  private async ensureRouteExists(routeId: string) {
    const count = await this.routes.count({ where: { id: routeId } });
    if (count === 0) throw new NotFoundException("Route not found");
  }

  private vehicleSummary(vehicle: Vehicle) {
    return {
      id: vehicle.id,
      routeId: vehicle.routeId,
      plateNumber: vehicle.plateNumber,
      isTrackingActive: vehicle.isTrackingActive,
      lat: vehicle.lastLocation?.coordinates[1] ?? null,
      lng: vehicle.lastLocation?.coordinates[0] ?? null,
      speedMetersPerSecond: vehicle.speedMetersPerSecond,
      lastSeenAt: vehicle.lastSeenAt,
    };
  }

  private ensureVehicleOperator(vehicle: Vehicle, operatorId: string) {
    if (vehicle.operatorId !== operatorId) {
      throw new ForbiddenException("Vehicle belongs to another operator");
    }
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

  private calculateBearing(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = (deg: number) => (deg * Math.PI) / 180;
    const toDeg = (rad: number) => (rad * 180) / Math.PI;

    const phi1 = toRad(lat1);
    const phi2 = toRad(lat2);
    const deltaLambda = toRad(lng2 - lng1);

    const y = Math.sin(deltaLambda) * Math.cos(phi2);
    const x =
      Math.cos(phi1) * Math.sin(phi2) -
      Math.sin(phi1) * Math.cos(phi2) * Math.cos(deltaLambda);

    const theta = Math.atan2(y, x);
    return (toDeg(theta) + 360) % 360;
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

  private findNearestPointOnRoute(
    routeStops: { stop: Stop }[],
    lat: number,
    lng: number,
  ): { lat: number; lng: number } {
    let bestDistance = Number.POSITIVE_INFINITY;
    let nearestPoint = { lat, lng };
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
      const dist = this.distanceMeters(lat, lng, projected.lat, projected.lng);
      if (dist < bestDistance) {
        bestDistance = dist;
        nearestPoint = { lat: projected.lat, lng: projected.lng };
      }
    }
    return nearestPoint;
  }

  private async markStaleVehiclesInactive(routeId: string) {
    await this.vehicles
      .createQueryBuilder()
      .update(Vehicle)
      .set({ isTrackingActive: false })
      .where('route_id = :routeId', { routeId })
      .andWhere('is_tracking_active = true')
      .andWhere("last_seen_at <= NOW() - INTERVAL '45 seconds'")
      .execute();
  }

  private isVehicleLive(vehicle: Vehicle, now = Date.now()) {
    return (
      vehicle.lastSeenAt !== null &&
      now - vehicle.lastSeenAt.getTime() <= TrackingService.activeVehicleWindowMs
    );
  }

  private etaConfidence(vehicle: Vehicle, distanceMeters: number, now = Date.now()) {
    const lastSeenSeconds = vehicle.lastSeenAt
      ? Math.max(0, Math.round((now - vehicle.lastSeenAt.getTime()) / 1000))
      : null;
    const speed = vehicle.speedMetersPerSecond ?? 0;
    let level: 'high' | 'medium' | 'low' = 'high';
    if (lastSeenSeconds === null || lastSeenSeconds > 30 || speed < 0.5) {
      level = 'low';
    } else if (lastSeenSeconds > 15 || speed < 1 || distanceMeters > 5000) {
      level = 'medium';
    }
    return {
      level,
      label:
        level === 'high'
          ? 'التتبع نشط'
          : level === 'medium'
            ? 'التتبع متوسط الدقة'
            : 'آخر تحديث قديم',
      lastSeenSeconds,
    };
  }

  private notificationHint(distanceMeters: number, etaMinutes: number) {
    if (distanceMeters <= 120 || etaMinutes <= 1) {
      return 'arrived';
    }
    if (distanceMeters <= 650 || etaMinutes <= 3) {
      return 'near';
    }
    return null;
  }

  private walkingRouteCacheKey(
    fromLat: number,
    fromLng: number,
    toLat: number,
    toLng: number,
  ) {
    const roundToFiveMeters = (value: number) => Math.round(value / 0.00005) * 0.00005;
    return [
      'walking-route',
      roundToFiveMeters(fromLat).toFixed(5),
      roundToFiveMeters(fromLng).toFixed(5),
      roundToFiveMeters(toLat).toFixed(5),
      roundToFiveMeters(toLng).toFixed(5),
    ].join(':');
  }

  private async cacheWalkingRoute(
    cacheKey: string,
    points: { lat: number; lng: number }[],
    roadAware: boolean,
  ) {
    const distanceMeters = this.pathDistanceMeters(points);
    const result = {
      points,
      distanceMeters: Math.round(distanceMeters),
      walkingMinutes: Math.max(1, Math.ceil(distanceMeters / 80)),
      roadAware,
      cached: false,
    };
    await this.redis.set(
      cacheKey,
      JSON.stringify({ ...result, cached: true }),
      'EX',
      TrackingService.walkingRouteCacheTtlSeconds,
    );
    return result;
  }

  private pathDistanceMeters(points: { lat: number; lng: number }[]) {
    let total = 0;
    for (let index = 1; index < points.length; index += 1) {
      total += this.distanceMeters(
        points[index - 1].lat,
        points[index - 1].lng,
        points[index].lat,
        points[index].lng,
      );
    }
    return total;
  }

  // ── Walking Route ────────────────────────────────────────────────────────────

  /**
   * Returns a list of lat/lng waypoints representing a walking path from
   * [fromLat, fromLng] to [toLat, toLng].
   *
   * Priority:
   *   1. Google Directions API (mode=walking) – only when GOOGLE_MAPS_API_KEY is set.
   *   2. OSRM public foot routing.
   *   3. Straight-line fallback (two points only).
   */
  async getWalkingRoute(
    fromLat: number,
    fromLng: number,
    toLat: number,
    toLng: number,
  ): Promise<{ points: { lat: number; lng: number }[] }> {
    const cacheKey = this.walkingRouteCacheKey(fromLat, fromLng, toLat, toLng);
    const cached = await this.redis.get(cacheKey);
    if (cached) {
      try {
        return JSON.parse(cached) as {
          points: { lat: number; lng: number }[];
          distanceMeters?: number;
          walkingMinutes?: number;
          cached?: boolean;
        };
      } catch {
        await this.redis.del(cacheKey);
      }
    }

    const straight = [
      { lat: fromLat, lng: fromLng },
      { lat: toLat, lng: toLng },
    ];

    // 1. Google Directions (walking)
    const googleKey = this.config.get<string>('GOOGLE_MAPS_API_KEY', '');
    if (googleKey) {
      try {
        const url =
          `https://maps.googleapis.com/maps/api/directions/json` +
          `?origin=${fromLat},${fromLng}` +
          `&destination=${toLat},${toLng}` +
          `&mode=walking` +
          `&key=${googleKey}`;
        const res = await fetch(url, { signal: AbortSignal.timeout(6_000) });
        if (res.ok) {
          const data = (await res.json()) as {
            routes?: { overview_polyline?: { points?: string } }[];
          };
          const encoded =
            data.routes?.[0]?.overview_polyline?.points;
          if (encoded) {
            const decoded = this.decodePolyline(encoded);
            if (decoded.length > 1) {
              return this.cacheWalkingRoute(cacheKey, decoded, true);
            }
          }
        }
      } catch {
        // fall through to OSRM
      }
    }

    // 2. OSRM foot routing
    try {
      const url =
        `https://router.project-osrm.org/route/v1/foot/` +
        `${fromLng},${fromLat};${toLng},${toLat}` +
        `?overview=full&geometries=geojson`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6_000) });
      if (res.ok) {
        const data = (await res.json()) as {
          routes?: { geometry?: { coordinates?: [number, number][] } }[];
        };
        const coords = data.routes?.[0]?.geometry?.coordinates;
        if (coords && coords.length > 1) {
          return this.cacheWalkingRoute(
            cacheKey,
            coords.map(([lng, lat]) => ({ lat, lng })),
            true,
          );
        }
      }
    } catch {
      // fall through to straight line
    }

    // 3. Straight-line fallback
    return this.cacheWalkingRoute(cacheKey, straight, false);
  }

  /** Decode a Google Maps encoded polyline string into lat/lng pairs. */
  private decodePolyline(encoded: string): { lat: number; lng: number }[] {
    const points: { lat: number; lng: number }[] = [];
    let index = 0;
    let lat = 0;
    let lng = 0;

    while (index < encoded.length) {
      let shift = 0;
      let result = 0;
      let byte: number;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += result & 1 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += result & 1 ? ~(result >> 1) : result >> 1;

      points.push({ lat: lat / 1e5, lng: lng / 1e5 });
    }

    return points;
  }
}
