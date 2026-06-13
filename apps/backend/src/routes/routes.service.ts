import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Brackets, Repository } from 'typeorm';
import { PaginatedResponse } from '../common/dto/pagination.dto';
import { CreateRouteDto, ListRoutesDto, NearbyRoutesDto, SearchRoutesDto } from './routes.dto';
import { TransitRoute } from './route.entity';

@Injectable()
export class RoutesService {
  constructor(@InjectRepository(TransitRoute) private readonly routes: Repository<TransitRoute>) {}

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

  create(dto: CreateRouteDto) {
    return this.routes.save(
      this.routes.create({
        ...dto,
        lastVerifiedAt: dto.lastVerifiedAt ? new Date(dto.lastVerifiedAt) : null,
      }),
    );
  }

  async update(id: string, dto: Partial<CreateRouteDto>) {
    await this.routes.update(id, {
      ...dto,
      lastVerifiedAt: dto.lastVerifiedAt ? new Date(dto.lastVerifiedAt) : undefined,
    });
    return this.detail(id);
  }
}
