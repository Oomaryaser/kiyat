import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SavedRoute } from './saved-route.entity';
import { SavedRoutesController } from './saved-routes.controller';
import { SavedRoutesService } from './saved-routes.service';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [TypeOrmModule.forFeature([SavedRoute]), AuthModule],
  controllers: [SavedRoutesController],
  providers: [SavedRoutesService],
})
export class SavedRoutesModule {}
