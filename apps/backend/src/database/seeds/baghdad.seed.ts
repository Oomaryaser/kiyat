import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { RouteStatus, RouteType, StopType, PassengerWaitStatus, UserRole } from '../../common/enums/transit.enums';
import { TransitRoute } from '../../routes/route.entity';
import { RouteStop } from '../../routes/route-stop.entity';
import { Stop } from '../../stops/stop.entity';
import { User } from '../../users/user.entity';
import { Vehicle } from '../../tracking/vehicle.entity';
import { CommunityReport } from '../../reports/community-report.entity';
import { SavedRoute } from '../../saved-routes/saved-route.entity';
import { PassengerWait } from '../../tracking/passenger-wait.entity';

ConfigModule.forRoot({ envFilePath: ['.env', '../../.env'] });
const config = new ConfigService();

const dataSource = new DataSource({
  type: 'postgres',
  url: config.getOrThrow<string>('DATABASE_URL'),
  entities: [TransitRoute, Stop, RouteStop, Vehicle, User, CommunityReport, SavedRoute, PassengerWait],
  synchronize: true,
});

const routes = [
  {
    nameAr: 'اختبار شمال بغداد - الكاظمية',
    nameEn: 'Test North Baghdad - Kadhimiya',
    stops: [
      ['الكاظمية', 'Kadhimiya', 33.3792, 44.3384, 'بداية خط الاختبار الشمالي'],
      ['العطيفية', 'Al-Atifiya', 33.3601, 44.3656, 'نقطة وسطية شمالية'],
      ['الوزيرية', 'Al-Waziriyah', 33.3565, 44.3927, 'نهاية خط الاختبار الشمالي'],
    ],
  },
  {
    nameAr: 'اختبار جنوب بغداد - الزعفرانية',
    nameEn: 'Test South Baghdad - Zafaraniya',
    stops: [
      ['الزعفرانية', 'Zafaraniya', 33.2357, 44.4929, 'بداية خط الاختبار الجنوبي'],
      ['جسر ديالى', 'Diyala Bridge', 33.2528, 44.5361, 'نقطة وسطية جنوبية'],
      ['بسماية', 'Bismayah', 33.1810, 44.6065, 'نهاية خط الاختبار الجنوبي'],
    ],
  },
  {
    nameAr: 'بغداد الجديدة - النهضة',
    nameEn: 'New Baghdad - Al-Nahdha',
    stops: [
      ['بغداد الجديدة', 'New Baghdad', 33.3009, 44.4927, 'بداية الخط قرب بغداد الجديدة'],
      ['شارع فلسطين', 'Palestine Street', 33.3238, 44.4569, 'نقطة وسطية على الطريق'],
      ['ساحة بيروت', 'Beirut Square', 33.3362, 44.4442, 'قرب قناة الجيش'],
      ['النهضة', 'Al-Nahdha', 33.3446, 44.4224, 'نهاية الخط قرب النهضة'],
    ],
  },
];

async function seed() {
  await dataSource.initialize();
  const routeRepo = dataSource.getRepository(TransitRoute);
  const stopRepo = dataSource.getRepository(Stop);
  const routeStopRepo = dataSource.getRepository(RouteStop);
  const vehicleRepo = dataSource.getRepository(Vehicle);
  const passengerWaitRepo = dataSource.getRepository(PassengerWait);
  const userRepo = dataSource.getRepository(User);

  await dataSource.query('TRUNCATE TABLE routes RESTART IDENTITY CASCADE');
  await dataSource.query('TRUNCATE TABLE users RESTART IDENTITY CASCADE');

  // Seed default operator users
  await userRepo.save(
    userRepo.create({
      phone: '07701234567',
      role: UserRole.Owner,
      nameAr: 'مالك كيات',
    }),
  );
  await userRepo.save(
    userRepo.create({
      phone: '07711112222',
      role: UserRole.Operator,
      nameAr: 'مشغل كيات',
    }),
  );
  await userRepo.save(
    userRepo.create({
      phone: '07722223333',
      role: UserRole.Support,
      nameAr: 'دعم كيات',
    }),
  );

  for (const routeData of routes) {
    const route = await routeRepo.save(
      routeRepo.create({
        nameAr: routeData.nameAr,
        nameEn: routeData.nameEn,
        routeType: RouteType.Kia,
        status: RouteStatus.Active,
        fareMin: 500,
        fareMax: 1000,
        operatingHoursStart: '06:00',
        operatingHoursEnd: '22:00',
        confidenceScore: 78,
        lastVerifiedAt: new Date(),
      }),
    );

    for (const [index, stopData] of routeData.stops.entries()) {
      const [nameAr, nameEn, lat, lng, landmarkAr] = stopData;
      const stop = await stopRepo.save(
        stopRepo.create({
          nameAr: String(nameAr),
          nameEn: String(nameEn),
          landmarkAr: String(landmarkAr),
          stopType: index === 0 || index === routeData.stops.length - 1 ? StopType.Fixed : StopType.Approximate,
          location: { type: 'Point', coordinates: [Number(lng), Number(lat)] },
        }),
      );
      await routeStopRepo.save(
        routeStopRepo.create({
          route,
          stop,
          stopSequence: index + 1,
          isMajor: index === 0 || index === routeData.stops.length - 1,
        }),
      );
    }

    const firstStop = routeData.stops[0];
    const secondStop = routeData.stops[Math.min(1, routeData.stops.length - 1)];
    await vehicleRepo.save([
      vehicleRepo.create({
        route,
        plateNumber: `KIY-${routeData.nameEn.slice(0, 3).toUpperCase()}-1`,
        isTrackingActive: true,
        lastSeenAt: new Date(),
        lastLocation: { type: 'Point', coordinates: [Number(firstStop[3]), Number(firstStop[2])] },
      }),
      vehicleRepo.create({
        route,
        plateNumber: `KIY-${routeData.nameEn.slice(0, 3).toUpperCase()}-2`,
        isTrackingActive: true,
        lastSeenAt: new Date(Date.now() - 180000),
        lastLocation: { type: 'Point', coordinates: [Number(secondStop[3]), Number(secondStop[2])] },
      }),
    ]);

    // Add two static test passenger waits at intermediate stops
    const stopsToWait = routeData.stops.slice(1, -1);
    for (const [idx, stopData] of stopsToWait.entries()) {
      const [nameAr, nameEn, lat, lng] = stopData;
      await passengerWaitRepo.save(
        passengerWaitRepo.create({
          route,
          anonymousSessionId: `test-passenger-${routeData.nameEn.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${idx + 1}`,
          pickupLocation: { type: 'Point', coordinates: [Number(lng), Number(lat)] },
          lastLocation: { type: 'Point', coordinates: [Number(lng), Number(lat)] },
          status: PassengerWaitStatus.Waiting,
        })
      );
    }
  }

  await dataSource.destroy();
  console.log(`Seeded ${routes.length} test Kia routes`);
}

void seed().catch((error) => {
  console.error(error);
  process.exit(1);
});
