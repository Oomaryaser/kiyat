import { IsUUID } from 'class-validator';

export class SaveRouteDto {
  @IsUUID()
  userId!: string;

  @IsUUID()
  routeId!: string;
}
