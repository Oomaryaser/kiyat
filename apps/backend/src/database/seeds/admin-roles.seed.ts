import "reflect-metadata";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { DataSource } from "typeorm";
import { UserRole } from "../../common/enums/transit.enums";
import { User } from "../../users/user.entity";

ConfigModule.forRoot({ envFilePath: [".env", "../../.env"] });
const config = new ConfigService();

const dataSource = new DataSource({
  type: "postgres",
  url: config.getOrThrow<string>("DATABASE_URL"),
  entities: [User],
  synchronize: false,
});

const testUsers: Array<Pick<User, "phone" | "role" | "nameAr">> = [
  {
    phone: "07701234567",
    role: UserRole.Owner,
    nameAr: "مالك كيات التجريبي",
  },
  {
    phone: "07733334444",
    role: UserRole.Admin,
    nameAr: "مدير كيات التجريبي",
  },
  {
    phone: "07711112222",
    role: UserRole.Operator,
    nameAr: "مشغل كيات التجريبي",
  },
  {
    phone: "07722223333",
    role: UserRole.Support,
    nameAr: "دعم كيات التجريبي",
  },
];

async function seedAdminRoles() {
  await dataSource.initialize();
  const userRepo = dataSource.getRepository(User);

  for (const testUser of testUsers) {
    const existing = await userRepo.findOne({ where: { phone: testUser.phone } });
    await userRepo.save(
      userRepo.create({
        ...existing,
        ...testUser,
      }),
    );
  }

  await dataSource.destroy();
  console.log(`Seeded ${testUsers.length} admin role test users`);
}

void seedAdminRoles().catch((error) => {
  console.error(error);
  process.exit(1);
});
