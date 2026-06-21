import { IsEnum, IsOptional, IsString, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../common/dto/pagination.dto';
import { ReportStatus, ReportType } from '../common/enums/transit.enums';

export class CreateReportDto {
  @IsUUID()
  routeId!: string;

  @IsOptional()
  @IsUUID()
  reporterId?: string;

  @IsEnum(ReportType)
  reportType!: ReportType;

  @IsString()
  description!: string;
}

export class ListReportsDto extends PaginationQueryDto {
  @IsOptional()
  @IsEnum(ReportStatus)
  status?: ReportStatus = ReportStatus.Pending;
}

export class ReviewReportDto {
  @IsEnum(ReportStatus)
  status!: ReportStatus.Approved | ReportStatus.Rejected;

  @IsOptional()
  @IsUUID()
  reviewedById?: string;
}
