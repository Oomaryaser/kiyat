import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { RouteStatus, RouteType, StopType } from '../../common/enums/transit.enums';
import { TransitRoute } from '../../routes/route.entity';
import { RouteStop } from '../../routes/route-stop.entity';
import { Stop } from '../../stops/stop.entity';
import { User } from '../../users/user.entity';
import { Vehicle } from '../../tracking/vehicle.entity';
import { CommunityReport } from '../../reports/community-report.entity';
import { SavedRoute } from '../../saved-routes/saved-route.entity';

ConfigModule.forRoot();
const config = new ConfigService();

const dataSource = new DataSource({
  type: 'postgres',
  url: config.getOrThrow<string>('DATABASE_URL'),
  entities: [TransitRoute, Stop, RouteStop, Vehicle, User, CommunityReport, SavedRoute],
  synchronize: true,
});

const routes = [
  {
    nameAr: 'الباب الشرقي - الكاظمية',
    nameEn: 'Bab Al-Sharqi - Kadhimiya',
    stops: [
      ['الباب الشرقي', 'Bab Al-Sharqi', 33.3152, 44.4161, 'قرب ساحة التحرير'],
      ['الصالحية', 'Al-Salihiya', 33.3236, 44.3959, 'قرب مبنى الإذاعة والتلفزيون'],
      ['العطيفية', 'Al-Atifiya', 33.3601, 44.3656, 'قرب الجسر'],
      ['الكاظمية', 'Kadhimiya', 33.3792, 44.3384, 'قرب الروضة الكاظمية'],
    ],
  },
  {
    nameAr: 'الباب الشرقي - المنصور',
    nameEn: 'Bab Al-Sharqi - Mansour',
    stops: [
      ['الباب الشرقي', 'Bab Al-Sharqi', 33.3152, 44.4161, 'قرب ساحة التحرير'],
      ['كرادة مريم', 'Karradat Maryam', 33.3127, 44.3928, 'قرب المنطقة الخضراء'],
      ['الحارثية', 'Al-Harthiya', 33.3165, 44.3578, 'قرب مول المنصور'],
      ['المنصور', 'Al-Mansour', 33.3159, 44.3447, 'شارع 14 رمضان'],
    ],
  },
  {
    nameAr: 'الكرادة - الجادرية',
    nameEn: 'Karrada - Jadriya',
    stops: [
      ['كرادة داخل', 'Karrada Dakhil', 33.3017, 44.4342, 'قرب شارع العطار'],
      ['الجامعة التكنولوجية', 'University of Technology', 33.3133, 44.4334, 'قرب الجامعة التكنولوجية'],
      ['الجادرية', 'Jadriya', 33.2739, 44.3775, 'قرب جامعة بغداد'],
    ],
  },
  {
    nameAr: 'الشعب - الباب المعظم',
    nameEn: 'Al-Shaab - Bab Al-Muadham',
    stops: [
      ['الشعب', 'Al-Shaab', 33.3909, 44.4551, 'قرب سوق الشعب'],
      ['حي تونس', 'Tunis District', 33.3714, 44.4244, 'قرب شارع فلسطين'],
      ['الوزيرية', 'Al-Waziriyah', 33.3565, 44.3927, 'قرب الجامعة المستنصرية'],
      ['الباب المعظم', 'Bab Al-Muadham', 33.3498, 44.3817, 'قرب وزارة الصحة'],
    ],
  },
  {
    nameAr: 'مدينة الصدر - ساحة الطيران',
    nameEn: 'Sadr City - Al-Tayaran Square',
    stops: [
      ['مدينة الصدر', 'Sadr City', 33.3684, 44.5087, 'قرب سوق مريدي'],
      ['جميلة', 'Jamila', 33.3542, 44.4781, 'قرب علوة جميلة'],
      ['ساحة بيروت', 'Beirut Square', 33.3362, 44.4442, 'قرب قناة الجيش'],
      ['ساحة الطيران', 'Al-Tayaran Square', 33.3185, 44.4221, 'قرب النصب'],
    ],
  },
];

async function seed() {
  await dataSource.initialize();
  const routeRepo = dataSource.getRepository(TransitRoute);
  const stopRepo = dataSource.getRepository(Stop);
  const routeStopRepo = dataSource.getRepository(RouteStop);
  const vehicleRepo = dataSource.getRepository(Vehicle);

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
  }

  await dataSource.destroy();
  console.log('Seeded 5 Baghdad Kia routes');
}

void seed().catch((error) => {
  console.error(error);
  process.exit(1);
});
