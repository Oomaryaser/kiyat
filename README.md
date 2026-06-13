# كيات

كيات is an Iraqi public transit information app. This repository is a Baghdad MVP monorepo with:

- `apps/mobile`: Flutter passenger app with Arabic RTL UI.
- `apps/backend`: NestJS API with PostgreSQL/PostGIS, Redis, JWT auth, Swagger, and Socket.IO tracking.
- `packages/shared-types`: Shared TypeScript interfaces and enums.
- `infra`: Docker Compose for local PostgreSQL/PostGIS and Redis.

## Quick Start

```bash
cd kiyat
cp .env.example .env
npm install
docker compose -f infra/docker-compose.yml up -d postgres redis
npm run backend:dev
```

Swagger is available at:

```text
http://localhost:3000/api/docs
```

Seed Baghdad sample routes after the database is running:

```bash
npm run backend:seed
```

## Backend Notes

The API includes:

- `POST /auth/send-otp`
- `POST /auth/verify-otp`
- `POST /auth/refresh`
- `GET /routes`
- `GET /routes/:id`
- `GET /routes/nearby?lat=&lng=&radius=`
- `GET /routes/search?from=&to=`
- `POST /routes`
- `PATCH /routes/:id`
- `GET /stops`
- `GET /stops/nearby?lat=&lng=&radius=`
- `POST /stops`
- `POST /reports`
- `GET /reports`
- `PATCH /reports/:id`
- `GET /saved-routes?userId=`
- `POST /saved-routes`
- `DELETE /saved-routes/:id`

Socket.IO tracking namespace:

```text
/tracking
```

Events:

- `vehicle:location` with `{ vehicleId, lat, lng }`
- `vehicle:subscribe` with `{ routeId }`
- `vehicle:update` broadcast to subscribers

OTP sending is stubbed and logs `123456` to the backend console.

## Mobile Notes

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_URL=http://localhost:3000
```

The theme is configured for Arabic-first RTL and the Tajawal font family. Add Tajawal font files or configure a font package before production release.

## Local Infra

```bash
docker compose -f infra/docker-compose.yml up --build
```

Services:

- PostgreSQL/PostGIS: `localhost:5432`
- Redis: `localhost:6379`
- Backend: `localhost:3000`
# kiyat
