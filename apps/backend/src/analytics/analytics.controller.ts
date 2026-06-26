import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { OperatorAuthGuard } from '../auth/operator-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { AnalyticsService } from './analytics.service';
import { UserRole } from '../common/enums/transit.enums';

@ApiTags('analytics')
@Controller('analytics')
@UseGuards(OperatorAuthGuard, RolesGuard)
@ApiBearerAuth()
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get('overview')
  @Roles(UserRole.Owner, UserRole.Admin, UserRole.Operator, UserRole.Support)
  overview() {
    return this.analytics.overview();
  }

  @Get('live-tracking')
  @Roles(UserRole.Owner, UserRole.Admin, UserRole.Operator)
  liveTracking() {
    return this.analytics.liveTracking();
  }
}
