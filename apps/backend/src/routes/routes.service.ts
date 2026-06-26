import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Brackets, Repository } from 'typeorm';
import { PaginatedResponse } from '../common/dto/pagination.dto';
import { CreateRouteDto, ListRoutesDto, NearbyRoutesDto, SearchRoutesDto } from './routes.dto';
import { TransitRoute } from './route.entity';
import { Stop } from '../stops/stop.entity';
import { RouteStop } from './route-stop.entity';
import { StopType } from '../common/enums/transit.enums';

@Injectable()
export class RoutesService {
  constructor(
    @InjectRepository(TransitRoute) private readonly routes: Repository<TransitRoute>,
    @InjectRepository(Stop) private readonly stops: Repository<Stop>,
    @InjectRepository(RouteStop) private readonly routeStops: Repository<RouteStop>,
  ) {}

  async list(query: ListRoutesDto): Promise<PaginatedResponse<TransitRoute>> {
    const qb = this.routes.createQueryBuilder('route');
    if (query.type) qb.andWhere('route.route_type = :type', { type: query.type });
    if (query.status) qb.andWhere('route.status = :status', { status: query.status });
    if (query.search) {
      qb.andWhere(
        new Brackets((where) => {
          where.where('route.name_ar ILIKE :search').orWhere('route.name_en ILIKE :search');
        }),
      ).setParameter('search', `%${query.search}%`);
    }
    const [data, total] = await qb
      .orderBy('route.name_ar', 'ASC')
      .skip((query.page - 1) * query.limit)
      .take(query.limit)
      .getManyAndCount();
    return { data, total, page: query.page, limit: query.limit };
  }

  async detail(id: string) {
    const route = await this.routes.findOne({
      where: { id },
      relations: { routeStops: true },
      order: { routeStops: { stopSequence: 'ASC' } },
    });
    if (!route) throw new NotFoundException('Route not found');
    return route;
  }

  async nearby(query: NearbyRoutesDto): Promise<PaginatedResponse<TransitRoute>> {
    const qb = this.routes
      .createQueryBuilder('route')
      .innerJoin('route.routeStops', 'routeStop')
      .innerJoin('routeStop.stop', 'stop')
      .where(
        'ST_DWithin(stop.location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :radius)',
        query,
      )
      .distinct(true)
      .skip((query.page - 1) * query.limit)
      .take(query.limit);
    const [data, total] = await qb.getManyAndCount();
    return { data, total, page: query.page, limit: query.limit };
  }

  async search(query: SearchRoutesDto): Promise<PaginatedResponse<TransitRoute>> {
    const termA = `%${query.from}%`;
    const termB = `%${query.to}%`;
    const qb = this.routes
      .createQueryBuilder('route')
      .leftJoin('route.routeStops', 'routeStop')
      .leftJoin('routeStop.stop', 'stop')
      .where('route.name_ar ILIKE :termA OR route.name_en ILIKE :termA OR stop.name_ar ILIKE :termA', { termA })
      .orWhere('route.name_ar ILIKE :termB OR route.name_en ILIKE :termB OR stop.name_ar ILIKE :termB', { termB })
      .distinct(true)
      .skip((query.page - 1) * query.limit)
      .take(query.limit);
    const [data, total] = await qb.getManyAndCount();
    return { data, total, page: query.page, limit: query.limit };
  }

  async create(dto: CreateRouteDto) {
    const { stops, ...routeData } = dto;
    const route = await this.routes.save(
      this.routes.create({
        ...routeData,
        lastVerifiedAt: dto.lastVerifiedAt ? new Date(dto.lastVerifiedAt) : null,
      }),
    );

    if (stops && stops.length > 0) {
      for (const [index, s] of stops.entries()) {
        const stop = await this.stops.save(
          this.stops.create({
            nameAr: s.nameAr,
            nameEn: s.nameEn,
            landmarkAr: s.nameAr,
            stopType: s.isMajor ? StopType.Fixed : StopType.Approximate,
            location: { type: 'Point', coordinates: [s.lng, s.lat] },
          })
        );
        await this.routeStops.save(
          this.routeStops.create({
            routeId: route.id,
            stopId: stop.id,
            stopSequence: index + 1,
            isMajor: s.isMajor ?? false,
          })
        );
      }
    }
    return this.detail(route.id);
  }

  async update(id: string, dto: Partial<CreateRouteDto>) {
    const route = await this.routes.findOne({ where: { id } });
    if (!route) throw new NotFoundException('Route not found');

    const { stops, ...routeData } = dto;

    await this.routes.save({
      ...route,
      ...routeData,
      lastVerifiedAt: dto.lastVerifiedAt ? new Date(dto.lastVerifiedAt) : undefined,
    });

    if (stops !== undefined) {
      // Clear old route stops
      await this.routeStops.delete({ routeId: id });

      if (stops && stops.length > 0) {
        for (const [index, s] of stops.entries()) {
          const stop = await this.stops.save(
            this.stops.create({
              nameAr: s.nameAr,
              nameEn: s.nameEn,
              landmarkAr: s.nameAr,
              stopType: s.isMajor ? StopType.Fixed : StopType.Approximate,
              location: { type: 'Point', coordinates: [s.lng, s.lat] },
            })
          );
          await this.routeStops.save(
            this.routeStops.create({
              routeId: id,
              stopId: stop.id,
              stopSequence: index + 1,
              isMajor: s.isMajor ?? false,
            })
          );
        }
      }
    }

    return this.detail(id);
  }
}
