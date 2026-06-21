import { Body, Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { SaveRouteDto } from './saved-routes.dto';
import { SavedRoutesService } from './saved-routes.service';
import { JwtAuthGuard, AuthenticatedRequest } from '../auth/jwt-auth.guard';

@ApiTags('saved-routes')
@Controller('saved-routes')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class SavedRoutesController {
  constructor(private readonly savedRoutes: SavedRoutesService) {}

  @Get()
  list(@Req() req: AuthenticatedRequest) {
    return this.savedRoutes.list(req.user.sub);
  }

  @Post()
  save(@Body() dto: SaveRouteDto, @Req() req: AuthenticatedRequest) {
    return this.savedRoutes.save(req.user.sub, dto.routeId);
  }

  @Delete(':id')
  remove(@Param('id') id: string, @Req() req: AuthenticatedRequest) {
    return this.savedRoutes.remove(id, req.user.sub);
  }
}
