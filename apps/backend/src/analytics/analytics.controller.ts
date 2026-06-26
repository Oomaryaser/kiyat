import { Controller, Get, Req, UseGuards, ForbiddenException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { OperatorAuthGuard, AuthenticatedOperatorRequest } from '../auth/operator-auth.guard';
import { AnalyticsService } from './analytics.service';
import { UserRole } from '../common/enums/transit.enums';

@ApiTags('analytics')
@Controller('analytics')
@UseGuards(OperatorAuthGuard)
@ApiBearerAuth()
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get('overview')
  overview(@Req() req: AuthenticatedOperatorRequest) {
    // Both Owner, Admin, Operator, Support can view overview metrics
    return this.analytics.overview();
  }

  @Get('live-tracking')
  liveTracking(@Req() req: AuthenticatedOperatorRequest) {
    // Support role is forbidden from live tracking map details
    if (req.user.role === UserRole.Support) {
      throw new ForbiddenException("Access Denied: Support role cannot view live tracking map");
    }
    return this.analytics.liveTracking();
  }
}
