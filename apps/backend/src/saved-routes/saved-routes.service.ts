import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SavedRoute } from './saved-route.entity';

@Injectable()
export class SavedRoutesService {
  constructor(@InjectRepository(SavedRoute) private readonly savedRoutes: Repository<SavedRoute>) {}

  list(userId: string) {
    return this.savedRoutes.find({ where: { user: { id: userId } }, order: { createdAt: 'DESC' } });
  }

  save(userId: string, routeId: string) {
    return this.savedRoutes.save(
      this.savedRoutes.create({
        user: { id: userId },
        route: { id: routeId },
      }),
    );
  }

  async remove(id: string, userId: string) {
    const saved = await this.savedRoutes.findOne({ where: { id }, relations: ['user'] });
    if (!saved) throw new NotFoundException('Saved route not found');
    if (saved.user.id !== userId) throw new ForbiddenException('You do not own this saved route');
    await this.savedRoutes.remove(saved);
    return { message: 'Saved route removed' };
  }
}
