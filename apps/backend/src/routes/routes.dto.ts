import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsISO8601, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';
import { PaginationQueryDto } from '../common/dto/pagination.dto';
import { RouteStatus, RouteType } from '../common/enums/transit.enums';

export class ListRoutesDto extends PaginationQueryDto {
  @IsOptional()
  @IsEnum(RouteType)
  type?: RouteType;

  @IsOptional()
  @IsEnum(RouteStatus)
  status?: RouteStatus;

  @IsOptional()
  @IsString()
  search?: string;
}

export class NearbyRoutesDto extends PaginationQueryDto {
  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;

  @Type(() => Number)
  @IsInt()
  @Min(100)
  @Max(10000)
  radius = 1000;
}

export class SearchRoutesDto extends PaginationQueryDto {
  @IsString()
  from!: string;

  @IsString()
  to!: string;
}

export class CreateRouteDto {
  @IsString()
  nameAr!: string;

  @IsString()
  nameEn!: string;

  @IsEnum(RouteType)
  routeType!: RouteType;

  @IsOptional()
  @IsEnum(RouteStatus)
  status?: RouteStatus;

  @IsInt()
  fareMin!: number;

  @IsInt()
  fareMax!: number;

  @IsString()
  operatingHoursStart!: string;

  @IsString()
  operatingHoursEnd!: string;

  @IsOptional()
  @IsInt()
  confidenceScore?: number;

  @IsOptional()
  @IsISO8601()
  lastVerifiedAt?: string;
}
