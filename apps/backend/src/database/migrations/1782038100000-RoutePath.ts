import { MigrationInterface, QueryRunner } from 'typeorm';

export class RoutePath1782038100000 implements MigrationInterface {
  name = 'RoutePath1782038100000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "routes"
      ADD COLUMN IF NOT EXISTS "route_path" jsonb
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "routes"
      DROP COLUMN IF EXISTS "route_path"
    `);
  }
}
