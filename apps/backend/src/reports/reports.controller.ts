import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CreateReportDto, ListReportsDto, ReviewReportDto } from './reports.dto';
import { ReportsService } from './reports.service';
import { JwtAuthGuard, AuthenticatedRequest } from '../auth/jwt-auth.guard';
import { OperatorAuthGuard, AuthenticatedOperatorRequest } from '../auth/operator-auth.guard';

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
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  list(@Query() query: ListReportsDto) {
    return this.reports.list(query);
  }

  @Patch(':id')
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  review(@Param('id') id: string, @Body() dto: ReviewReportDto, @Req() req: AuthenticatedOperatorRequest) {
    return this.reports.review(id, { ...dto, reviewedById: req.user.sub });
  }
}
