import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
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
}
