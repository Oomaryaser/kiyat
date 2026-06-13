import { Column, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn } from 'typeorm';
import { Stop } from '../stops/stop.entity';
import { TransitRoute } from './route.entity';

@Entity('route_stops')
export class RouteStop {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ManyToOne(() => TransitRoute, (route) => route.routeStops, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'route_id' })
  route!: TransitRoute;

  @Column({ name: 'route_id' })
  routeId!: string;

  @ManyToOne(() => Stop, (stop) => stop.routeStops, { eager: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'stop_id' })
  stop!: Stop;

  @Column({ name: 'stop_id' })
  stopId!: string;

  @Column({ name: 'stop_sequence', type: 'integer' })
  stopSequence!: number;

  @Column({ name: 'is_major', type: 'boolean', default: false })
  isMajor!: boolean;
}
