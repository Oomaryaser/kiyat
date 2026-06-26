import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CreateReportDto, ListReportsDto, ReviewReportDto } from './reports.dto';
import { ReportsService } from './reports.service';
import { JwtAuthGuard, AuthenticatedRequest } from '../auth/jwt-auth.guard';
import { OperatorAuthGuard, AuthenticatedOperatorRequest } from '../auth/operator-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { UserRole } from '../common/enums/transit.enums';

@ApiTags('reports')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Post()
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  create(@Body() dto: CreateReportDto, @Req() req: AuthenticatedRequest) {
    return this.reports.create(dto, req.user.sub);
  }

  @Get()
  @UseGuards(OperatorAuthGuard, RolesGuard)
  @Roles(UserRole.Owner, UserRole.Admin, UserRole.Support)
  @ApiBearerAuth()
  list(@Query() query: ListReportsDto) {
    return this.reports.list(query);
  }

  @Patch(':id')
  @UseGuards(OperatorAuthGuard, RolesGuard)
  @Roles(UserRole.Owner, UserRole.Admin, UserRole.Support)
  @ApiBearerAuth()
  review(@Param('id') id: string, @Body() dto: ReviewReportDto, @Req() req: AuthenticatedOperatorRequest) {
    return this.reports.review(id, { ...dto, reviewedById: req.user.sub });
  }
}
