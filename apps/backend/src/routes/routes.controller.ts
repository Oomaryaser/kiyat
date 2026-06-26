import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards, ForbiddenException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CreateRouteDto, ListRoutesDto, NearbyRoutesDto, SearchRoutesDto } from './routes.dto';
import { RoutesService } from './routes.service';
import { OperatorAuthGuard, AuthenticatedOperatorRequest } from '../auth/operator-auth.guard';
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
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  create(@Body() dto: CreateRouteDto, @Req() req: AuthenticatedOperatorRequest) {
    if (req.user.role !== UserRole.Owner && req.user.role !== UserRole.Admin) {
      throw new ForbiddenException("Access Denied: Only Owner or Admin can manage routes");
    }
    return this.routes.create(dto);
  }

  @Patch(':id')
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  update(@Param('id') id: string, @Body() dto: Partial<CreateRouteDto>, @Req() req: AuthenticatedOperatorRequest) {
    if (req.user.role !== UserRole.Owner && req.user.role !== UserRole.Admin) {
      throw new ForbiddenException("Access Denied: Only Owner or Admin can manage routes");
    }
    return this.routes.update(id, dto);
  }
}
