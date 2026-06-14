import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { RouteArrivalQueryDto, StartPassengerWaitDto, UpdatePassengerWaitDto } from './tracking.dto';
import { TrackingService } from './tracking.service';

@ApiTags('tracking')
@Controller('tracking')
export class TrackingController {
  constructor(private readonly tracking: TrackingService) {}

  @Get('routes/:routeId/arrival')
  routeArrival(@Param('routeId') routeId: string, @Query() query: RouteArrivalQueryDto) {
    return this.tracking.getRouteArrival(routeId, query);
  }

  @Post('routes/:routeId/passenger-waits')
  startPassengerWait(@Param('routeId') routeId: string, @Body() dto: StartPassengerWaitDto) {
    return this.tracking.startPassengerWait(routeId, dto);
  }

  @Post('passenger-waits/:waitId/location')
  updatePassengerWait(@Param('waitId') waitId: string, @Body() dto: UpdatePassengerWaitDto) {
    return this.tracking.updatePassengerWaitLocation(waitId, dto);
  }

  @Post('passenger-waits/:waitId/cancel')
  cancelPassengerWait(@Param('waitId') waitId: string) {
    return this.tracking.cancelPassengerWait(waitId);
  }

  @Get('routes/:routeId/passenger-waits/active')
  activePassengerWaits(@Param('routeId') routeId: string) {
    return this.tracking.getActivePassengerWaits(routeId);
  }
}
