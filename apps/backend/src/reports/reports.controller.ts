import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CreateReportDto, ListReportsDto, ReviewReportDto } from './reports.dto';
import { ReportsService } from './reports.service';

@ApiTags('reports')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Post()
  create(@Body() dto: CreateReportDto) {
    return this.reports.create(dto);
  }

  @Get()
  list(@Query() query: ListReportsDto) {
    return this.reports.list(query);
  }

  @Patch(':id')
  review(@Param('id') id: string, @Body() dto: ReviewReportDto) {
    return this.reports.review(id, dto);
  }
}
