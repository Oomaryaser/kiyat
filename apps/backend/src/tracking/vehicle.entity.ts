import {
  Column,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from "typeorm";
import { TransitRoute } from "../routes/route.entity";
import { User } from "../users/user.entity";

@Entity("vehicles")
@Index(["isTrackingActive", "lastSeenAt"])
export class Vehicle {
  @PrimaryGeneratedColumn("uuid")
  id!: string;

  @ManyToOne(() => TransitRoute, { onDelete: "CASCADE" })
  @JoinColumn({ name: "route_id" })
  route!: TransitRoute;

  @Column({ name: "route_id" })
  routeId!: string;

  @ManyToOne(() => User, { nullable: true, onDelete: "SET NULL" })
  @JoinColumn({ name: "operator_id" })
  operator!: User | null;

  @Column({ name: "operator_id", type: "uuid", nullable: true })
  operatorId!: string | null;

  @Column({ name: "plate_number", type: "varchar", nullable: true })
  plateNumber!: string | null;

  @Column({
    name: "last_location",
    type: "geometry",
    spatialFeatureType: "Point",
    srid: 4326,
    nullable: true,
  })
  lastLocation!: { type: "Point"; coordinates: [number, number] } | null;

  @Column({ name: "last_seen_at", type: "timestamp", nullable: true })
  lastSeenAt!: Date | null;

  @Column({
    name: "speed_meters_per_second",
    type: "double precision",
    nullable: true,
  })
  speedMetersPerSecond!: number | null;

  @Column({ name: "is_tracking_active", default: false })
  isTrackingActive!: boolean;
}
