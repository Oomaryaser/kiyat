import { Column, CreateDateColumn, Entity, Index, OneToMany, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { RouteStatus, RouteType } from '../common/enums/transit.enums';
import { RouteStop } from './route-stop.entity';

@Entity('routes')
@Index(['status'])
export class TransitRoute {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'name_ar' })
  nameAr!: string;

  @Column({ name: 'name_en' })
  nameEn!: string;

  @Column({ name: 'route_type', type: 'enum', enum: RouteType })
  routeType!: RouteType;

  @Column({ type: 'enum', enum: RouteStatus, default: RouteStatus.Unverified })
  status!: RouteStatus;

  @Column({ name: 'fare_min', type: 'integer' })
  fareMin!: number;

  @Column({ name: 'fare_max', type: 'integer' })
  fareMax!: number;

  @Column({ name: 'operating_hours_start', type: 'time' })
  operatingHoursStart!: string;

  @Column({ name: 'operating_hours_end', type: 'time' })
  operatingHoursEnd!: string;

  @Column({ name: 'confidence_score', type: 'integer', default: 50 })
  confidenceScore!: number;

  @Column({ name: 'last_verified_at', type: 'timestamp', nullable: true })
  lastVerifiedAt!: Date | null;

  @OneToMany(() => RouteStop, (routeStop) => routeStop.route, { cascade: true })
  routeStops!: RouteStop[];

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
