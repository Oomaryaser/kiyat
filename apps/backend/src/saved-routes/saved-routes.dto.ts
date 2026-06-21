import { IsOptional, IsUUID } from 'class-validator';

export class SaveRouteDto {
  @IsOptional()
  @IsUUID()
  userId?: string;

  @IsUUID()
  routeId!: string;
}
