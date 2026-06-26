import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CreateTripRatingDto } from './trip-ratings.dto';
import { TripRating } from './trip-rating.entity';

@Injectable()
export class TripRatingsService {
  constructor(
    @InjectRepository(TripRating)
    private readonly tripRatings: Repository<TripRating>,
  ) {}

  create(dto: CreateTripRatingDto, passengerId?: string) {
    return this.tripRatings.save(
      this.tripRatings.create({
        routeId: dto.routeId,
        passengerWaitId: dto.passengerWaitId ?? null,
        passengerId: passengerId ?? null,
        rating: dto.rating,
        crowdingLevel: dto.crowdingLevel ?? null,
        priceFair: dto.priceFair ?? null,
        cleanlinessRating: dto.cleanlinessRating ?? null,
        comment: dto.comment?.trim() || null,
      }),
    );
  }

  async routeSummary(routeId: string) {
    const raw = await this.tripRatings
      .createQueryBuilder('rating')
      .select('COUNT(*)', 'count')
      .addSelect('AVG(rating.rating)', 'averageRating')
      .addSelect('AVG(rating.cleanlinessRating)', 'averageCleanliness')
      .where('rating.route_id = :routeId', { routeId })
      .getRawOne<{
        count: string;
        averageRating: string | null;
        averageCleanliness: string | null;
      }>();

    return {
      routeId,
      count: Number(raw?.count ?? 0),
      averageRating: raw?.averageRating ? Number(raw.averageRating) : null,
      averageCleanliness: raw?.averageCleanliness
        ? Number(raw.averageCleanliness)
        : null,
    };
  }

  listAll() {
    return this.tripRatings.find({
      relations: ['route', 'passenger'],
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }
}
