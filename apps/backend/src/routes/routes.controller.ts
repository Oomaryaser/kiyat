import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CreateRouteDto, ListRoutesDto, NearbyRoutesDto, SearchRoutesDto } from './routes.dto';
import { RoutesService } from './routes.service';

@ApiTags('routes')
@Controller('routes')
export class RoutesController {
  constructor(private readonly routes: RoutesService) {}

  @Get()
  list(@Query() query: ListRoutesDto) {
    return this.routes.list(query);
  }

  @Get('nearby')
  nearby(@Query() query: NearbyRoutesDto) {
    return this.routes.nearby(query);
  }

  @Get('search')
  search(@Query() query: SearchRoutesDto) {
    return this.routes.search(query);
  }

  @Get(':id')
  detail(@Param('id') id: string) {
    return this.routes.detail(id);
  }

  @Post()
  create(@Body() dto: CreateRouteDto) {
    return this.routes.create(dto);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: Partial<CreateRouteDto>) {
    return this.routes.update(id, dto);
  }
}
