import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthenticatedRequest, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { OperatorAuthGuard } from '../auth/operator-auth.guard';
import { CreateTripRatingDto } from './trip-ratings.dto';
import { TripRatingsService } from './trip-ratings.service';

@ApiTags('trip-ratings')
@Controller('trip-ratings')
export class TripRatingsController {
  constructor(private readonly tripRatings: TripRatingsService) {}

  @Post()
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  create(@Body() dto: CreateTripRatingDto, @Req() req: AuthenticatedRequest) {
    return this.tripRatings.create(dto, req.user.sub);
  }

  @Get('routes/:routeId/summary')
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  routeSummary(@Param('routeId') routeId: string) {
    return this.tripRatings.routeSummary(routeId);
  }
}
