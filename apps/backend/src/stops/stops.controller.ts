import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { PaginationQueryDto } from '../common/dto/pagination.dto';
import { CreateStopDto, NearbyStopsDto } from './stops.dto';
import { StopsService } from './stops.service';

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
  create(@Body() dto: CreateStopDto) {
    return this.stops.create(dto);
  }
}
