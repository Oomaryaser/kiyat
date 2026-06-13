import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
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
import { Vehicle } from './tracking/vehicle.entity';
import { User } from './users/user.entity';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        url: config.getOrThrow<string>('DATABASE_URL'),
        entities: [TransitRoute, Stop, RouteStop, Vehicle, User, CommunityReport, SavedRoute],
        synchronize: config.get<string>('TYPEORM_SYNC', 'true') === 'true',
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
  ],
})
export class AppModule {}
