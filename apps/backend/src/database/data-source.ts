import { DataSource } from 'typeorm';
import { join } from 'path';
import { config } from 'dotenv';

config({ path: join(__dirname, '../../../../.env') });

export default new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  entities: [join(__dirname, '../**/*.entity{.ts,.js}')],
  migrations: [join(__dirname, 'migrations/**/*{.ts,.js}')],
  synchronize: false,
});
