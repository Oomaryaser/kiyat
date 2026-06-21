import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { TransitRoute } from '../routes/route.entity';
import { PassengerWait } from '../tracking/passenger-wait.entity';
import { Vehicle } from '../tracking/vehicle.entity';
import { TripRating } from '../trip-ratings/trip-rating.entity';
import { AnalyticsController } from './analytics.controller';
import { AnalyticsService } from './analytics.service';

@Module({
  imports: [
    AuthModule,
    TypeOrmModule.forFeature([PassengerWait, Vehicle, TripRating, TransitRoute]),
  ],
  controllers: [AnalyticsController],
  providers: [AnalyticsService],
})
export class AnalyticsModule {}
