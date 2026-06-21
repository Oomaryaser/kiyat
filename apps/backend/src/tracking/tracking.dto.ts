import { Type } from "class-transformer";
import { IsNumber, IsOptional, IsString, IsUUID, Matches } from "class-validator";

export class RouteArrivalQueryDto {
  @IsOptional()
  @IsUUID()
  pickupStopId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lng?: number;
}

export class StartPassengerWaitDto {
  @IsString()
  @Matches(/^(passenger|test)-\d+$/, { message: "Invalid anonymous session ID format" })
  anonymousSessionId!: string;

  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;
}

export class UpdatePassengerWaitDto {
  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  accuracyMeters?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  speedMetersPerSecond?: number;
}

export class CreateDriverVehicleDto {
  @IsOptional()
  @IsString()
  plateNumber?: string;
}

export class UpdateVehicleLocationDto {
  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  speedMetersPerSecond?: number;
}
