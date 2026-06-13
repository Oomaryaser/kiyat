import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { RouteArrivalQueryDto } from './tracking.dto';
import { TrackingService } from './tracking.service';

@ApiTags('tracking')
@Controller('tracking')
export class TrackingController {
  constructor(private readonly tracking: TrackingService) {}

  @Get('routes/:routeId/arrival')
  routeArrival(@Param('routeId') routeId: string, @Query() query: RouteArrivalQueryDto) {
    return this.tracking.getRouteArrival(routeId, query);
  }
}
