import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { TripRating } from './trip-rating.entity';
import { TripRatingsController } from './trip-ratings.controller';
import { TripRatingsService } from './trip-ratings.service';

@Module({
  imports: [TypeOrmModule.forFeature([TripRating]), AuthModule],
  controllers: [TripRatingsController],
  providers: [TripRatingsService],
  exports: [TripRatingsService, TypeOrmModule],
})
export class TripRatingsModule {}
