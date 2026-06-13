import { Column, CreateDateColumn, Entity, OneToMany, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { StopType } from '../common/enums/transit.enums';
import { RouteStop } from '../routes/route-stop.entity';

@Entity('stops')
export class Stop {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'name_ar' })
  nameAr!: string;

  @Column({ name: 'name_en' })
  nameEn!: string;

  @Column({
    type: 'geometry',
    spatialFeatureType: 'Point',
    srid: 4326,
  })
  location!: { type: 'Point'; coordinates: [number, number] };

  @Column({ name: 'landmark_ar', type: 'varchar', nullable: true })
  landmarkAr!: string | null;

  @Column({ name: 'stop_type', type: 'enum', enum: StopType, default: StopType.Approximate })
  stopType!: StopType;

  @OneToMany(() => RouteStop, (routeStop) => routeStop.stop)
  routeStops!: RouteStop[];

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
