import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PaginationQueryDto, PaginatedResponse } from '../common/dto/pagination.dto';
import { CreateStopDto, NearbyStopsDto } from './stops.dto';
import { Stop } from './stop.entity';

@Injectable()
export class StopsService {
  constructor(@InjectRepository(Stop) private readonly stops: Repository<Stop>) {}

  async list(query: PaginationQueryDto): Promise<PaginatedResponse<Stop>> {
    const [data, total] = await this.stops.findAndCount({
      order: { nameAr: 'ASC' },
      skip: (query.page - 1) * query.limit,
      take: query.limit,
    });
    return { data, total, page: query.page, limit: query.limit };
  }

  async nearby(query: NearbyStopsDto): Promise<PaginatedResponse<Stop>> {
    const qb = this.stops
      .createQueryBuilder('stop')
      .where(
        'ST_DWithin(stop.location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :radius)',
        query,
      )
      .skip((query.page - 1) * query.limit)
      .take(query.limit);
    const [data, total] = await qb.getManyAndCount();
    return { data, total, page: query.page, limit: query.limit };
  }

  create(dto: CreateStopDto) {
    return this.stops.save(
      this.stops.create({
        nameAr: dto.nameAr,
        nameEn: dto.nameEn,
        landmarkAr: dto.landmarkAr ?? null,
        stopType: dto.stopType,
        location: { type: 'Point', coordinates: [dto.lng, dto.lat] },
      }),
    );
  }
}
