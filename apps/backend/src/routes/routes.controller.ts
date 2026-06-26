import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CreateRouteDto, ListRoutesDto, NearbyRoutesDto, SearchRoutesDto } from './routes.dto';
import { RoutesService } from './routes.service';
import { OperatorAuthGuard } from '../auth/operator-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { UserRole } from '../common/enums/transit.enums';

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
  @UseGuards(OperatorAuthGuard, RolesGuard)
  @Roles(UserRole.Owner, UserRole.Admin)
  @ApiBearerAuth()
  create(@Body() dto: CreateRouteDto) {
    return this.routes.create(dto);
  }

  @Patch(':id')
  @UseGuards(OperatorAuthGuard, RolesGuard)
  @Roles(UserRole.Owner, UserRole.Admin)
  @ApiBearerAuth()
  update(@Param('id') id: string, @Body() dto: Partial<CreateRouteDto>) {
    return this.routes.update(id, dto);
  }
}
