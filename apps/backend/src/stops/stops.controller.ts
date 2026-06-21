import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { PaginationQueryDto } from '../common/dto/pagination.dto';
import { CreateStopDto, NearbyStopsDto } from './stops.dto';
import { StopsService } from './stops.service';
import { OperatorAuthGuard } from '../auth/operator-auth.guard';

@ApiTags('stops')
@Controller('stops')
export class StopsController {
  constructor(private readonly stops: StopsService) {}

  @Get()
  list(@Query() query: PaginationQueryDto) {
    return this.stops.list(query);
  }

  @Get('nearby')
  nearby(@Query() query: NearbyStopsDto) {
    return this.stops.nearby(query);
  }

  @Post()
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  create(@Body() dto: CreateStopDto) {
    return this.stops.create(dto);
  }
}
