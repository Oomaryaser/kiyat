import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PaginatedResponse } from '../common/dto/pagination.dto';
import { CommunityReport } from './community-report.entity';
import { CreateReportDto, ListReportsDto, ReviewReportDto } from './reports.dto';

@Injectable()
export class ReportsService {
  constructor(@InjectRepository(CommunityReport) private readonly reports: Repository<CommunityReport>) {}

  create(dto: CreateReportDto, reporterId: string) {
    return this.reports.save(this.reports.create({ ...dto, reporterId }));
  }

  async list(query: ListReportsDto): Promise<PaginatedResponse<CommunityReport>> {
    const [data, total] = await this.reports.findAndCount({
      where: query.status ? { status: query.status } : {},
      order: { createdAt: 'DESC' },
      skip: (query.page - 1) * query.limit,
      take: query.limit,
    });
    return { data, total, page: query.page, limit: query.limit };
  }

  async review(id: string, dto: ReviewReportDto) {
    const report = await this.reports.findOne({ where: { id } });
    if (!report) throw new NotFoundException('Report not found');
    report.status = dto.status;
    report.reviewedById = dto.reviewedById ?? null;
    return this.reports.save(report);
  }
}
