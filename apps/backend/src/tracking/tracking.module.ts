import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { RouteStop } from '../routes/route-stop.entity';
import { TransitRoute } from '../routes/route.entity';
import { PassengerWait } from './passenger-wait.entity';
import { TrackingController } from './tracking.controller';
import { Vehicle } from './vehicle.entity';
import { TrackingGateway } from './tracking.gateway';
import { TrackingService } from './tracking.service';

@Module({
  imports: [ConfigModule, TypeOrmModule.forFeature([Vehicle, TransitRoute, RouteStop, PassengerWait])],
  controllers: [TrackingController],
  providers: [TrackingGateway, TrackingService],
})
export class TrackingModule {}
