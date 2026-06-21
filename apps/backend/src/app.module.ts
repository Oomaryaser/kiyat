import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AnalyticsModule } from './analytics/analytics.module';
import { AuthModule } from './auth/auth.module';
import { CommunityReport } from './reports/community-report.entity';
import { ReportsModule } from './reports/reports.module';
import { RouteStop } from './routes/route-stop.entity';
import { TransitRoute } from './routes/route.entity';
import { RoutesModule } from './routes/routes.module';
import { SavedRoute } from './saved-routes/saved-route.entity';
import { SavedRoutesModule } from './saved-routes/saved-routes.module';
import { Stop } from './stops/stop.entity';
import { StopsModule } from './stops/stops.module';
import { TrackingModule } from './tracking/tracking.module';
import { PassengerWait } from './tracking/passenger-wait.entity';
import { Vehicle } from './tracking/vehicle.entity';
import { TripRating } from './trip-ratings/trip-rating.entity';
import { TripRatingsModule } from './trip-ratings/trip-ratings.module';
import { User } from './users/user.entity';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ envFilePath: ['.env', '../../.env'], isGlobal: true }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        url: config.getOrThrow<string>('DATABASE_URL'),
        entities: [TransitRoute, Stop, RouteStop, Vehicle, PassengerWait, User, CommunityReport, SavedRoute, TripRating],
        synchronize: config.get<string>('TYPEORM_SYNC', 'false') === 'true',
        logging: config.get<string>('TYPEORM_LOGGING', 'false') === 'true',
      }),
    }),
    AuthModule,
    RoutesModule,
    StopsModule,
    TrackingModule,
    ReportsModule,
    SavedRoutesModule,
    UsersModule,
    TripRatingsModule,
    AnalyticsModule,
  ],
})
export class AppModule {}
