import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SavedRoute } from './saved-route.entity';
import { SaveRouteDto } from './saved-routes.dto';

@Injectable()
export class SavedRoutesService {
  constructor(@InjectRepository(SavedRoute) private readonly savedRoutes: Repository<SavedRoute>) {}

  list(userId: string) {
    return this.savedRoutes.find({ where: { user: { id: userId } }, order: { createdAt: 'DESC' } });
  }

  save(dto: SaveRouteDto) {
    return this.savedRoutes.save(
      this.savedRoutes.create({
        user: { id: dto.userId },
        route: { id: dto.routeId },
      }),
    );
  }

  async remove(id: string) {
    await this.savedRoutes.delete(id);
    return { message: 'Saved route removed' };
  }
}
