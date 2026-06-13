import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { SaveRouteDto } from './saved-routes.dto';
import { SavedRoutesService } from './saved-routes.service';

@ApiTags('saved-routes')
@Controller('saved-routes')
export class SavedRoutesController {
  constructor(private readonly savedRoutes: SavedRoutesService) {}

  @Get()
  list(@Query('userId') userId: string) {
    return this.savedRoutes.list(userId);
  }

  @Post()
  save(@Body() dto: SaveRouteDto) {
    return this.savedRoutes.save(dto);
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.savedRoutes.remove(id);
  }
}
