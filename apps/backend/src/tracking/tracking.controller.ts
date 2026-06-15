import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import {
  AuthenticatedOperatorRequest,
  OperatorAuthGuard,
} from "../auth/operator-auth.guard";
import {
  CreateDriverVehicleDto,
  RouteArrivalQueryDto,
  StartPassengerWaitDto,
  UpdatePassengerWaitDto,
  UpdateVehicleLocationDto,
} from "./tracking.dto";
import { TrackingService } from "./tracking.service";

@ApiTags("tracking")
@Controller("tracking")
export class TrackingController {
  constructor(private readonly tracking: TrackingService) {}

  @Get("routes/:routeId/arrival")
  routeArrival(
    @Param("routeId") routeId: string,
    @Query() query: RouteArrivalQueryDto,
  ) {
    return this.tracking.getRouteArrival(routeId, query);
  }

  @Get("routes/:routeId/vehicles")
  routeVehicles(@Param("routeId") routeId: string) {
    return this.tracking.listRouteVehicles(routeId);
  }

  @Post("routes/:routeId/vehicles")
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  createDriverVehicle(
    @Param("routeId") routeId: string,
    @Body() dto: CreateDriverVehicleDto,
    @Req() request: AuthenticatedOperatorRequest,
  ) {
    return this.tracking.createDriverVehicle(
      routeId,
      dto.plateNumber,
      request.user.sub,
    );
  }

  @Post("vehicles/:vehicleId/location")
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  updateVehicleLocation(
    @Param("vehicleId") vehicleId: string,
    @Body() dto: UpdateVehicleLocationDto,
    @Req() request: AuthenticatedOperatorRequest,
  ) {
    return this.tracking.updateVehicleLocation({
      vehicleId,
      operatorId: request.user.sub,
      ...dto,
    });
  }

  @Post("vehicles/:vehicleId/stop")
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  stopVehicleTracking(
    @Param("vehicleId") vehicleId: string,
    @Req() request: AuthenticatedOperatorRequest,
  ) {
    return this.tracking.stopVehicleTracking(vehicleId, request.user.sub);
  }

  @Post("routes/:routeId/passenger-waits")
  startPassengerWait(
    @Param("routeId") routeId: string,
    @Body() dto: StartPassengerWaitDto,
  ) {
    return this.tracking.startPassengerWait(routeId, dto);
  }

  @Post("passenger-waits/:waitId/location")
  updatePassengerWait(
    @Param("waitId") waitId: string,
    @Body() dto: UpdatePassengerWaitDto,
  ) {
    return this.tracking.updatePassengerWaitLocation(waitId, dto);
  }

  @Post("passenger-waits/:waitId/cancel")
  cancelPassengerWait(@Param("waitId") waitId: string) {
    return this.tracking.cancelPassengerWait(waitId);
  }

  @Get("routes/:routeId/passenger-waits/active")
  activePassengerWaits(@Param("routeId") routeId: string) {
    return this.tracking.getActivePassengerWaits(routeId);
  }
}
