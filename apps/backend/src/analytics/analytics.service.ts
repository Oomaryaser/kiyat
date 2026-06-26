import { Injectable, Inject } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import Redis from 'ioredis';
import { Repository } from 'typeorm';
import { PassengerWaitStatus } from '../common/enums/transit.enums';
import { TransitRoute } from '../routes/route.entity';
import { PassengerWait } from '../tracking/passenger-wait.entity';
import { TripRating } from '../trip-ratings/trip-rating.entity';
import { Vehicle } from '../tracking/vehicle.entity';

@Injectable()
export class AnalyticsService {
  constructor(
    @InjectRepository(PassengerWait)
    private readonly passengerWaits: Repository<PassengerWait>,
    @InjectRepository(Vehicle)
    private readonly vehicles: Repository<Vehicle>,
    @InjectRepository(TripRating)
    private readonly tripRatings: Repository<TripRating>,
    @InjectRepository(TransitRoute)
    private readonly routes: Repository<TransitRoute>,
    @Inject('REDIS_CLIENT') private readonly redis: Redis,
  ) {}

  async overview() {
    const activeWaits = await this.passengerWaits.count({
      where: { status: PassengerWaitStatus.Waiting },
    });
    const activeVehicles = await this.vehicles
      .createQueryBuilder('vehicle')
      .where('vehicle.is_tracking_active = true')
      .andWhere("vehicle.last_seen_at > NOW() - INTERVAL '45 seconds'")
      .getCount();

    const waitStats = await this.passengerWaits
      .createQueryBuilder('wait')
      .select("AVG(EXTRACT(EPOCH FROM (wait.boarded_at - wait.created_at)) / 60)", 'averageWaitMinutes')
      .addSelect('COUNT(*)', 'boardedCount')
      .where('wait.status = :status', { status: PassengerWaitStatus.Boarded })
      .andWhere('wait.boarded_at IS NOT NULL')
      .getRawOne<{ averageWaitMinutes: string | null; boardedCount: string }>();

    const ratingStats = await this.tripRatings
      .createQueryBuilder('rating')
      .select('COUNT(*)', 'ratingCount')
      .addSelect('AVG(rating.rating)', 'averageRating')
      .getRawOne<{ ratingCount: string; averageRating: string | null }>();

    const busiestRoutes = await this.passengerWaits
      .createQueryBuilder('wait')
      .innerJoin(TransitRoute, 'route', 'route.id = wait.route_id')
      .select('route.id', 'routeId')
      .addSelect('route.name_ar', 'routeNameAr')
      .addSelect('COUNT(*)', 'waitCount')
      .where("wait.created_at > NOW() - INTERVAL '24 hours'")
      .groupBy('route.id')
      .addGroupBy('route.name_ar')
      .orderBy('COUNT(*)', 'DESC')
      .limit(8)
      .getRawMany<{ routeId: string; routeNameAr: string; waitCount: string }>();

    const routeCount = await this.routes.count();

    return {
      activeWaits,
      activeVehicles,
      routeCount,
      boardedCount: Number(waitStats?.boardedCount ?? 0),
      averageWaitMinutes: waitStats?.averageWaitMinutes
        ? Number(waitStats.averageWaitMinutes)
        : null,
      ratingCount: Number(ratingStats?.ratingCount ?? 0),
      averageRating: ratingStats?.averageRating
        ? Number(ratingStats.averageRating)
        : null,
      busiestRoutes: busiestRoutes.map((route) => ({
        routeId: route.routeId,
        routeNameAr: route.routeNameAr,
        waitCount: Number(route.waitCount),
      })),
    };
  }

  async liveTracking() {
    // 1. Fetch active vehicles (active in last 5 minutes)
    const rawVehicles = await this.vehicles
      .createQueryBuilder('vehicle')
      .leftJoinAndSelect('vehicle.route', 'route')
      .leftJoinAndSelect('vehicle.operator', 'operator')
      .where('vehicle.is_tracking_active = true')
      .andWhere("vehicle.last_seen_at > NOW() - INTERVAL '5 minutes'")
      .getMany();

    // Map active vehicles in parallel fetching heading from Redis
    const vehicles = await Promise.all(
      rawVehicles.map(async (v) => {
        const bearingRaw = await this.redis.get(`vehicle:${v.id}:bearing`);
        const heading = bearingRaw ? parseInt(bearingRaw, 10) : 0;
        return {
          id: v.id,
          driverName: v.operator?.nameAr || 'سائق كية',
          routeId: v.routeId,
          routeName: v.route?.nameAr || 'خط غير معروف',
          lat: v.lastLocation?.coordinates[1] ?? 0.0,
          lng: v.lastLocation?.coordinates[0] ?? 0.0,
          lastSeenAt: v.lastSeenAt ? v.lastSeenAt.toISOString() : null,
          speed: v.speedMetersPerSecond ?? 0.0,
          heading,
        };
      })
    );

    // 2. Fetch active passenger waits (waiting in last 15 minutes)
    const rawWaits = await this.passengerWaits
      .createQueryBuilder('wait')
      .leftJoinAndSelect('wait.route', 'route')
      .where('wait.status = :status', { status: PassengerWaitStatus.Waiting })
      .andWhere("wait.updated_at > NOW() - INTERVAL '15 minutes'")
      .getMany();

    // Group and aggregate passenger waits to protect privacy (3 decimals ~100m)
    const zonesMap = new Map<string, {
      routeId: string;
      routeName: string;
      lat: number;
      lng: number;
      updatedAt: Date;
      count: number;
    }>();

    for (const w of rawWaits) {
      const rawLat = w.lastLocation?.coordinates[1] ?? 0.0;
      const rawLng = w.lastLocation?.coordinates[0] ?? 0.0;
      const roundedLat = Math.round(rawLat * 1000) / 1000;
      const roundedLng = Math.round(rawLng * 1000) / 1000;

      const key = `${roundedLat},${roundedLng},${w.routeId}`;
      const existing = zonesMap.get(key);
      if (existing) {
        existing.count += 1;
        if (w.updatedAt > existing.updatedAt) {
          existing.updatedAt = w.updatedAt;
        }
      } else {
        zonesMap.set(key, {
          routeId: w.routeId,
          routeName: w.route?.nameAr || 'خط غير معروف',
          lat: roundedLat,
          lng: roundedLng,
          updatedAt: w.updatedAt,
          count: 1,
        });
      }
    }

    const passengerWaits = Array.from(zonesMap.entries()).map(([key, z], idx) => ({
      id: `zone-${idx + 1}`,
      routeId: z.routeId,
      routeName: z.routeName,
      lat: z.lat,
      lng: z.lng,
      updatedAt: z.updatedAt.toISOString(),
      count: z.count,
    }));

    // 3. Create summary metrics
    const summary = {
      activeVehicles: vehicles.length,
      waitingPassengers: rawWaits.length,
      passengerZones: passengerWaits.length,
      updatedAt: new Date().toISOString(),
    };

    return {
      vehicles,
      passengerWaits,
      summary,
    };
  }
}
