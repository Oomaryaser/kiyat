import { Column, CreateDateColumn, Entity, Index, JoinColumn, ManyToOne, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { PassengerWaitStatus } from '../common/enums/transit.enums';
import { TransitRoute } from '../routes/route.entity';

@Entity('passenger_waits')
@Index(['status', 'updatedAt'])
@Index(['routeId', 'status', 'updatedAt'])
export class PassengerWait {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ManyToOne(() => TransitRoute, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'route_id' })
  route!: TransitRoute;

  @Column({ name: 'route_id' })
  routeId!: string;

  @Column({ name: 'anonymous_session_id' })
  anonymousSessionId!: string;

  @Column({
    name: 'pickup_location',
    type: 'geometry',
    spatialFeatureType: 'Point',
    srid: 4326,
  })
  pickupLocation!: { type: 'Point'; coordinates: [number, number] };

  @Column({
    name: 'last_location',
    type: 'geometry',
    spatialFeatureType: 'Point',
    srid: 4326,
  })
  lastLocation!: { type: 'Point'; coordinates: [number, number] };

  @Column({ name: 'pickup_progress_meters', type: 'double precision', default: 0 })
  pickupProgressMeters!: number;

  @Column({ name: 'last_progress_meters', type: 'double precision', default: 0 })
  lastProgressMeters!: number;

  @Column({ type: 'enum', enum: PassengerWaitStatus, default: PassengerWaitStatus.Waiting })
  status!: PassengerWaitStatus;

  @Column({ name: 'boarded_at', type: 'timestamp', nullable: true })
  boardedAt!: Date | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
