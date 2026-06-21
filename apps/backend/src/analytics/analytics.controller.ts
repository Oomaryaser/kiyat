import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { OperatorAuthGuard } from '../auth/operator-auth.guard';
import { AnalyticsService } from './analytics.service';

@ApiTags('analytics')
@Controller('analytics')
@UseGuards(OperatorAuthGuard)
@ApiBearerAuth()
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get('overview')
  overview() {
    return this.analytics.overview();
  }
}
