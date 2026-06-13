import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CommunityReport } from './community-report.entity';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({
  imports: [TypeOrmModule.forFeature([CommunityReport])],
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}
