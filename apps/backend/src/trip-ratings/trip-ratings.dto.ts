import { Type } from 'class-transformer';
import { IsBoolean, IsEnum, IsInt, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';
import { TripCrowdingLevel } from '../common/enums/transit.enums';

export class CreateTripRatingDto {
  @IsUUID()
  routeId!: string;

  @IsOptional()
  @IsUUID()
  passengerWaitId?: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsEnum(TripCrowdingLevel)
  crowdingLevel?: TripCrowdingLevel;

  @IsOptional()
  @IsBoolean()
  priceFair?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5)
  cleanlinessRating?: number;

  @IsOptional()
  @IsString()
  comment?: string;
}
