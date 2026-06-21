import { MigrationInterface, QueryRunner } from 'typeorm';

export class TripRatings1782037000000 implements MigrationInterface {
  name = 'TripRatings1782037000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);
    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_type WHERE typname = 'trip_ratings_crowding_level_enum'
        ) THEN
          CREATE TYPE "public"."trip_ratings_crowding_level_enum" AS ENUM('low', 'medium', 'high');
        END IF;
      END$$;
    `);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "trip_ratings" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "route_id" uuid NOT NULL,
        "passenger_wait_id" uuid,
        "passenger_id" uuid,
        "rating" integer NOT NULL,
        "crowding_level" "public"."trip_ratings_crowding_level_enum",
        "price_fair" boolean,
        "cleanliness_rating" integer,
        "comment" text,
        "created_at" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_trip_ratings_id" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_trip_ratings_route') THEN
          ALTER TABLE "trip_ratings" ADD CONSTRAINT "FK_trip_ratings_route" FOREIGN KEY ("route_id") REFERENCES "routes"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_trip_ratings_passenger_wait') THEN
          ALTER TABLE "trip_ratings" ADD CONSTRAINT "FK_trip_ratings_passenger_wait" FOREIGN KEY ("passenger_wait_id") REFERENCES "passenger_waits"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_trip_ratings_passenger') THEN
          ALTER TABLE "trip_ratings" ADD CONSTRAINT "FK_trip_ratings_passenger" FOREIGN KEY ("passenger_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
        END IF;
      END$$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "trip_ratings" DROP CONSTRAINT "FK_trip_ratings_passenger"`);
    await queryRunner.query(`ALTER TABLE "trip_ratings" DROP CONSTRAINT "FK_trip_ratings_passenger_wait"`);
    await queryRunner.query(`ALTER TABLE "trip_ratings" DROP CONSTRAINT "FK_trip_ratings_route"`);
    await queryRunner.query(`DROP TABLE "trip_ratings"`);
    await queryRunner.query(`DROP TYPE "public"."trip_ratings_crowding_level_enum"`);
  }
}
