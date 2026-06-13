import { CreateDateColumn, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn, Unique } from 'typeorm';
import { TransitRoute } from '../routes/route.entity';
import { User } from '../users/user.entity';

@Entity('saved_routes')
@Unique(['user', 'route'])
export class SavedRoute {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user!: User;

  @ManyToOne(() => TransitRoute, { eager: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'route_id' })
  route!: TransitRoute;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
