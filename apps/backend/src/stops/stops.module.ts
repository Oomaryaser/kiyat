import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Stop } from './stop.entity';
import { StopsController } from './stops.controller';
import { StopsService } from './stops.service';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [TypeOrmModule.forFeature([Stop]), AuthModule],
  controllers: [StopsController],
  providers: [StopsService],
})
export class StopsModule {}
