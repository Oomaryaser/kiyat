import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';
import { PaginationQueryDto } from '../common/dto/pagination.dto';
import { StopType } from '../common/enums/transit.enums';

export class NearbyStopsDto extends PaginationQueryDto {
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

export class CreateStopDto {
  @IsString()
  nameAr!: string;

  @IsString()
  nameEn!: string;

  @IsNumber()
  lat!: number;

  @IsNumber()
  lng!: number;

  @IsOptional()
  @IsString()
  landmarkAr?: string;

  @IsOptional()
  @IsEnum(StopType)
  stopType?: StopType;
}
