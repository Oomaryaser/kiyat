import { Column, CreateDateColumn, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn } from 'typeorm';
import { ReportStatus, ReportType } from '../common/enums/transit.enums';
import { TransitRoute } from '../routes/route.entity';
import { User } from '../users/user.entity';

@Entity('community_reports')
export class CommunityReport {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ManyToOne(() => TransitRoute, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'route_id' })
  route!: TransitRoute;

  @Column({ name: 'route_id' })
  routeId!: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'reporter_id' })
  reporter!: User;

  @Column({ name: 'reporter_id' })
  reporterId!: string;

  @Column({ name: 'report_type', type: 'enum', enum: ReportType })
  reportType!: ReportType;

  @Column({ type: 'text' })
  description!: string;

  @Column({ type: 'enum', enum: ReportStatus, default: ReportStatus.Pending })
  status!: ReportStatus;

  @ManyToOne(() => User, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'reviewed_by' })
  reviewedBy!: User | null;

  @Column({ name: 'reviewed_by', type: 'uuid', nullable: true })
  reviewedById!: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
