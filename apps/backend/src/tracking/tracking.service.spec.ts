import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ConfigService } from '@nestjs/config';
import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { TrackingService } from './tracking.service';
import { Vehicle } from './vehicle.entity';
import { TransitRoute } from '../routes/route.entity';
import { PassengerWait } from './passenger-wait.entity';
import { PassengerWaitStatus } from '../common/enums/transit.enums';

function calculateBearing(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const toDeg = (rad: number) => (rad * 180) / Math.PI;

  const phi1 = toRad(lat1);
  const phi2 = toRad(lat2);
  const deltaLambda = toRad(lng2 - lng1);

  const y = Math.sin(deltaLambda) * Math.cos(phi2);
  const x =
    Math.cos(phi1) * Math.sin(phi2) -
    Math.sin(phi1) * Math.cos(phi2) * Math.cos(deltaLambda);

  const theta = Math.atan2(y, x);
  return (toDeg(theta) + 360) % 360;
}

describe('TrackingService', () => {
  let service: TrackingService;
  let vehicleRepo: any;
  let routeRepo: any;
  let passengerWaitRepo: any;
  let store: Record<string, string>;
  let redisClient: any;

  const mockRoute = {
    id: 'route-1',
    routeStops: [
      {
        stopSequence: 1,
        stop: {
          id: 'stop-1',
          nameAr: 'Stop 1',
          location: { type: 'Point', coordinates: [44.4000, 33.3000] },
        },
      },
      {
        stopSequence: 2,
        stop: {
          id: 'stop-2',
          nameAr: 'Stop 2',
          location: { type: 'Point', coordinates: [44.4050, 33.3050] },
        },
      },
    ],
  };

  beforeEach(async () => {
    store = {};
    redisClient = {
      get: jest.fn().mockImplementation(async (key: string) => store[key] || null),
      set: jest.fn().mockImplementation(async (key: string, val: string) => {
        store[key] = val.toString();
        return 'OK';
      }),
      del: jest.fn().mockImplementation(async (key: string) => {
        delete store[key];
        return 1;
      }),
      incr: jest.fn().mockImplementation(async (key: string) => {
        const curr = parseInt(store[key] || '0', 10);
        const next = curr + 1;
        store[key] = next.toString();
        return next;
      }),
      expire: jest.fn().mockResolvedValue(1),
    };

    vehicleRepo = {
      findOne: jest.fn(),
      find: jest.fn(),
      save: jest.fn((val) => Promise.resolve(val)),
      create: jest.fn(),
    };

    routeRepo = {
      findOne: jest.fn().mockResolvedValue(mockRoute),
      count: jest.fn().mockResolvedValue(1),
    };

    passengerWaitRepo = {
      findOne: jest.fn(),
      save: jest.fn((val) => Promise.resolve(val)),
      create: jest.fn(),
      update: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        TrackingService,
        {
          provide: getRepositoryToken(Vehicle),
          useValue: vehicleRepo,
        },
        {
          provide: getRepositoryToken(TransitRoute),
          useValue: routeRepo,
        },
        {
          provide: getRepositoryToken(PassengerWait),
          useValue: passengerWaitRepo,
        },
        {
          provide: ConfigService,
          useValue: {
            get: jest.fn().mockReturnValue('redis://localhost:6379'),
          },
        },
        {
          provide: 'REDIS_CLIENT',
          useValue: redisClient,
        },
      ],
    }).compile();

    service = module.get<TrackingService>(TrackingService);
  });

  describe('Boarding Detection', () => {
    it('should confirm boarding when passenger is close, speeds match, bearing matches, and sync has run long enough', async () => {
      const waitSession = {
        id: 'wait-1',
        routeId: 'route-1',
        anonymousSessionId: 'session-123',
        status: PassengerWaitStatus.Waiting,
        createdAt: new Date(Date.now() - 70000), // > 60s
        pickupLocation: { type: 'Point', coordinates: [44.4000, 33.3000] },
        lastLocation: { type: 'Point', coordinates: [44.4000, 33.3000] },
        pickupProgressMeters: 0,
        lastProgressMeters: 0,
        boardedAt: null,
      };

      const activeVehicle = {
        id: 'vehicle-1',
        routeId: 'route-1',
        operatorId: 'operator-1',
        plateNumber: 'كية ١',
        isTrackingActive: true,
        lastSeenAt: new Date(),
        speedMetersPerSecond: 5.0,
        lastLocation: { type: 'Point', coordinates: [44.4001, 33.3001] }, // close to passenger update (coordinates 33.30005, 44.40005)
      };

      passengerWaitRepo.findOne.mockResolvedValue(waitSession);
      vehicleRepo.find.mockResolvedValue([activeVehicle]);

      // Calculate bearing from lastLocation (33.3, 44.4) to new location (33.30005, 44.40005)
      const passengerBearing = calculateBearing(33.3, 44.4, 33.30005, 44.40005);
      store['vehicle:vehicle-1:bearing'] = passengerBearing.toString();
      
      // Seed sync key in redis for > 20s
      store['wait:wait-1:sync:vehicle-1'] = (Date.now() - 25000).toString();

      const result = await service.updatePassengerWaitLocation(
        'wait-1',
        {
          lat: 33.30005,
          lng: 44.40005,
          accuracyMeters: 10.0,
          speedMetersPerSecond: 5.0,
        },
        'session-123',
      );

      expect(result.status).toBe(PassengerWaitStatus.Boarded);
      expect(result.boardedAt).toBeInstanceOf(Date);
    });

    it('should NOT confirm boarding when passenger is close but bearings are not aligned', async () => {
      const waitSession = {
        id: 'wait-1',
        routeId: 'route-1',
        anonymousSessionId: 'session-123',
        status: PassengerWaitStatus.Waiting,
        createdAt: new Date(Date.now() - 70000), // > 60s
        pickupLocation: { type: 'Point', coordinates: [44.4000, 33.3000] },
        lastLocation: { type: 'Point', coordinates: [44.4000, 33.3000] },
        pickupProgressMeters: 0,
        lastProgressMeters: 0,
        boardedAt: null,
      };

      const activeVehicle = {
        id: 'vehicle-1',
        routeId: 'route-1',
        operatorId: 'operator-1',
        plateNumber: 'كية ١',
        isTrackingActive: true,
        lastSeenAt: new Date(),
        speedMetersPerSecond: 5.0,
        lastLocation: { type: 'Point', coordinates: [44.4001, 33.3001] },
      };

      passengerWaitRepo.findOne.mockResolvedValue(waitSession);
      vehicleRepo.find.mockResolvedValue([activeVehicle]);

      const passengerBearing = calculateBearing(33.3, 44.4, 33.30005, 44.40005);
      // set vehicle bearing completely misaligned (e.g. passengerBearing + 90 deg)
      store['vehicle:vehicle-1:bearing'] = ((passengerBearing + 90) % 360).toString();
      store['wait:wait-1:sync:vehicle-1'] = (Date.now() - 25000).toString();

      const result = await service.updatePassengerWaitLocation(
        'wait-1',
        {
          lat: 33.30005,
          lng: 44.40005,
          accuracyMeters: 10.0,
          speedMetersPerSecond: 5.0,
        },
        'session-123',
      );

      expect(result.status).toBe(PassengerWaitStatus.Waiting);
    });

    it('should NOT confirm boarding under proximity rule if vehicle has not moved >= 25m', async () => {
      const waitSession = {
        id: 'wait-1',
        routeId: 'route-1',
        anonymousSessionId: 'session-123',
        status: PassengerWaitStatus.Waiting,
        createdAt: new Date(Date.now() - 70000), // > 60s
        pickupLocation: { type: 'Point', coordinates: [44.4000, 33.3000] },
        lastLocation: { type: 'Point', coordinates: [44.4000, 33.3000] },
        pickupProgressMeters: 0,
        lastProgressMeters: 0,
        boardedAt: null,
      };

      // Vehicle is close to passenger, has tracking active, but hasn't moved
      const activeVehicle = {
        id: 'vehicle-1',
        routeId: 'route-1',
        operatorId: 'operator-1',
        plateNumber: 'كية ١',
        isTrackingActive: true,
        lastSeenAt: new Date(),
        speedMetersPerSecond: 5.0,
        lastLocation: { type: 'Point', coordinates: [44.4001, 33.3001] },
      };

      passengerWaitRepo.findOne.mockResolvedValue(waitSession);
      vehicleRepo.find.mockResolvedValue([activeVehicle]);

      // Seed meeting key in redis indicating proximity check started 15s ago at the same coordinates
      store['wait:wait-1:meeting:vehicle-1'] = JSON.stringify({
        startedAt: Date.now() - 15000,
        startLat: 33.3001,
        startLng: 44.4001,
      });

      const result = await service.updatePassengerWaitLocation(
        'wait-1',
        {
          lat: 33.30005,
          lng: 44.40005,
          accuracyMeters: 10.0,
          speedMetersPerSecond: 0.0,
        },
        'session-123',
      );

      expect(result.status).toBe(PassengerWaitStatus.Waiting);
    });
  });

  describe('Wait Session Ownership', () => {
    it('should throw ForbiddenException if anonymousSessionId does not match during update', async () => {
      const waitSession = {
        id: 'wait-1',
        anonymousSessionId: 'owner-session-id',
        status: PassengerWaitStatus.Waiting,
      };
      passengerWaitRepo.findOne.mockResolvedValue(waitSession);

      await expect(
        service.updatePassengerWaitLocation('wait-1', { lat: 33.3, lng: 44.4 }, 'intruder-session-id'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should throw ForbiddenException if anonymousSessionId does not match during cancel', async () => {
      const waitSession = {
        id: 'wait-1',
        anonymousSessionId: 'owner-session-id',
        status: PassengerWaitStatus.Waiting,
      };
      passengerWaitRepo.findOne.mockResolvedValue(waitSession);

      await expect(
        service.cancelPassengerWait('wait-1', 'intruder-session-id'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should throw ForbiddenException if anonymousSessionId does not match during board', async () => {
      const waitSession = {
        id: 'wait-1',
        anonymousSessionId: 'owner-session-id',
        status: PassengerWaitStatus.Waiting,
      };
      passengerWaitRepo.findOne.mockResolvedValue(waitSession);

      await expect(
        service.boardPassengerWait('wait-1', 'intruder-session-id'),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  describe('Wait Operations', () => {
    it('should cancel wait successfully and set status to Cancelled', async () => {
      const waitSession = {
        id: 'wait-1',
        anonymousSessionId: 'owner-id',
        status: PassengerWaitStatus.Waiting,
      };
      passengerWaitRepo.findOne.mockResolvedValue(waitSession);

      const result = await service.cancelPassengerWait('wait-1', 'owner-id');
      expect(result.status).toBe(PassengerWaitStatus.Cancelled);
    });

    it('should manually board wait successfully, transition status to Boarded, and clean up Redis keys', async () => {
      const waitSession = {
        id: 'wait-1',
        routeId: 'route-1',
        anonymousSessionId: 'owner-id',
        status: PassengerWaitStatus.Waiting,
        boardedAt: null,
      };
      passengerWaitRepo.findOne.mockResolvedValue(waitSession);

      const activeVehicle = { id: 'vehicle-1' };
      vehicleRepo.find.mockResolvedValue([activeVehicle]);

      store['wait:wait-1:meeting:vehicle-1'] = 'meeting-active';
      store['wait:wait-1:sync:vehicle-1'] = 'sync-active';
      store['wait:wait-1:active_candidate'] = 'candidate-active';

      const result = await service.boardPassengerWait('wait-1', 'owner-id');
      expect(result.status).toBe(PassengerWaitStatus.Boarded);
      expect(result.boardedAt).toBeInstanceOf(Date);

      // Verify Redis keys are deleted
      expect(store['wait:wait-1:meeting:vehicle-1']).toBeUndefined();
      expect(store['wait:wait-1:sync:vehicle-1']).toBeUndefined();
      expect(store['wait:wait-1:active_candidate']).toBeUndefined();
    });
  });
});
