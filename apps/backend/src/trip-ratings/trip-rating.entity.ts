import { Column, CreateDateColumn, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn } from 'typeorm';
import { TripCrowdingLevel } from '../common/enums/transit.enums';
import { TransitRoute } from '../routes/route.entity';
import { PassengerWait } from '../tracking/passenger-wait.entity';
import { User } from '../users/user.entity';

@Entity('trip_ratings')
export class TripRating {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ManyToOne(() => TransitRoute, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'route_id' })
  route!: TransitRoute;

  @Column({ name: 'route_id' })
  routeId!: string;

  @ManyToOne(() => PassengerWait, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'passenger_wait_id' })
  passengerWait!: PassengerWait | null;

  @Column({ name: 'passenger_wait_id', type: 'uuid', nullable: true })
  passengerWaitId!: string | null;

  @ManyToOne(() => User, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'passenger_id' })
  passenger!: User | null;

  @Column({ name: 'passenger_id', type: 'uuid', nullable: true })
  passengerId!: string | null;

  @Column({ type: 'int' })
  rating!: number;

  @Column({ name: 'crowding_level', type: 'enum', enum: TripCrowdingLevel, nullable: true })
  crowdingLevel!: TripCrowdingLevel | null;

  @Column({ name: 'price_fair', type: 'boolean', nullable: true })
  priceFair!: boolean | null;

  @Column({ name: 'cleanliness_rating', type: 'int', nullable: true })
  cleanlinessRating!: number | null;

  @Column({ type: 'text', nullable: true })
  comment!: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
