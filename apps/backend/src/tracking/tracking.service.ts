import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TransitRoute } from '../routes/route.entity';
import { Stop } from '../stops/stop.entity';
import { RouteArrivalQueryDto } from './tracking.dto';
import { Vehicle } from './vehicle.entity';

export interface VehicleLocationPayload {
  vehicleId: string;
  lat: number;
  lng: number;
}

@Injectable()
export class TrackingService {
  constructor(
    @InjectRepository(Vehicle) private readonly vehicles: Repository<Vehicle>,
    @InjectRepository(TransitRoute) private readonly routes: Repository<TransitRoute>,
  ) {}

  async updateVehicleLocation(payload: VehicleLocationPayload) {
    const vehicle = await this.vehicles.findOne({ where: { id: payload.vehicleId } });
    if (!vehicle) throw new NotFoundException('Vehicle not found');
    vehicle.lastLocation = { type: 'Point', coordinates: [payload.lng, payload.lat] };
    vehicle.lastSeenAt = new Date();
    vehicle.isTrackingActive = true;
    return this.vehicles.save(vehicle);
  }

  async getRouteArrival(routeId: string, query: RouteArrivalQueryDto) {
    const route = await this.routes.findOne({
      where: { id: routeId },
      relations: { routeStops: true },
      order: { routeStops: { stopSequence: 'ASC' } },
    });
    if (!route) throw new NotFoundException('Route not found');

    const orderedStops = [...route.routeStops].sort((a, b) => a.stopSequence - b.stopSequence);
    if (orderedStops.length === 0) throw new NotFoundException('Route has no path anchors');

    const explicitPickupAnchor = orderedStops.find((routeStop) => routeStop.stopId === query.pickupStopId);
    const pickupLat = explicitPickupAnchor?.stop.location.coordinates[1] ?? query.lat ?? orderedStops[0].stop.location.coordinates[1];
    const pickupLng = explicitPickupAnchor?.stop.location.coordinates[0] ?? query.lng ?? orderedStops[0].stop.location.coordinates[0];
    const pickupProgressMeters = this.progressAlongRouteMeters(orderedStops, pickupLat, pickupLng);
    const nearestPickupAnchor = this.nearestRouteStop(orderedStops, pickupLat, pickupLng) ?? orderedStops[0];

    const activeVehicles = await this.vehicles.find({
      where: { routeId, isTrackingActive: true },
    });

    const candidates = activeVehicles
      .filter((vehicle) => vehicle.lastLocation)
      .map((vehicle) => {
        const vehiclePoint = vehicle.lastLocation!.coordinates;
        const nearestStop = this.nearestRouteStop(orderedStops, vehiclePoint[1], vehiclePoint[0]);
        const vehicleProgressMeters = this.progressAlongRouteMeters(orderedStops, vehiclePoint[1], vehiclePoint[0]);
        const remainingOnRouteMeters = pickupProgressMeters - vehicleProgressMeters;
        const hasPassedPickup = remainingOnRouteMeters < -50;
        const distanceMeters = Math.max(
          0,
          Math.round(hasPassedPickup ? this.distanceMeters(vehiclePoint[1], vehiclePoint[0], pickupLat, pickupLng) : remainingOnRouteMeters),
        );
        return {
          vehicleId: vehicle.id,
          plateNumber: vehicle.plateNumber,
          distanceMeters,
          etaMinutes: Math.max(1, Math.round(distanceMeters / 366)),
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

    const upcoming = candidates.filter((candidate) => !candidate.hasPassedPickup);
    const selectedVehicle = upcoming[0] ?? null;
    const nextCycleVehicle = selectedVehicle ? null : candidates[0] ?? null;

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
      skippedPassedVehicles: candidates.filter((candidate) => candidate.hasPassedPickup).slice(0, 3),
      alternatives: upcoming.slice(1, 4),
      message: selectedVehicle
        ? 'هذه أقرب كية بعدها ما وصلت لمكان صعودك على نفس اتجاه الخط'
        : nextCycleVehicle
          ? 'الكيات الظاهرة عدّت مكان صعودك، ننتظر كية بعدها على نفس الاتجاه'
          : 'ماكو تتبع حي حالياً لهذا الخط',
    };
  }

  private nearestRouteStop(routeStops: { stop: Stop; stopSequence: number }[], lat?: number, lng?: number) {
    if (lat === undefined || lng === undefined) return null;
    return routeStops
      .map((routeStop) => ({
        routeStop,
        distance: this.distanceMeters(lat, lng, routeStop.stop.location.coordinates[1], routeStop.stop.location.coordinates[0]),
      }))
      .sort((a, b) => a.distance - b.distance)[0]?.routeStop;
  }

  private distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number) {
    const earthRadius = 6371000;
    const toRad = (value: number) => (value * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  private progressAlongRouteMeters(routeStops: { stop: Stop }[], lat: number, lng: number) {
    let bestProgress = 0;
    let bestDistance = Number.POSITIVE_INFINITY;
    let accumulated = 0;

    for (let index = 0; index < routeStops.length - 1; index += 1) {
      const start = routeStops[index].stop.location.coordinates;
      const end = routeStops[index + 1].stop.location.coordinates;
      const segmentMeters = this.distanceMeters(start[1], start[0], end[1], end[0]);
      const projected = this.projectToSegment(lat, lng, start[1], start[0], end[1], end[0]);
      const distanceToSegment = this.distanceMeters(lat, lng, projected.lat, projected.lng);
      if (distanceToSegment < bestDistance) {
        bestDistance = distanceToSegment;
        bestProgress = accumulated + segmentMeters * projected.t;
      }
      accumulated += segmentMeters;
    }

    return bestProgress;
  }

  private projectToSegment(lat: number, lng: number, startLat: number, startLng: number, endLat: number, endLng: number) {
    const x = lng;
    const y = lat;
    const x1 = startLng;
    const y1 = startLat;
    const x2 = endLng;
    const y2 = endLat;
    const dx = x2 - x1;
    const dy = y2 - y1;
    const lengthSquared = dx * dx + dy * dy;
    const rawT = lengthSquared === 0 ? 0 : ((x - x1) * dx + (y - y1) * dy) / lengthSquared;
    const t = Math.max(0, Math.min(1, rawT));
    return { lat: y1 + dy * t, lng: x1 + dx * t, t };
  }
}
