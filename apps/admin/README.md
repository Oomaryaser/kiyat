# Kiyat Admin

Next.js dashboard for the Kiyat super owner/admin console.

## Local Development

From the repository root:

```bash
npm run admin:dev
```

The dashboard runs on:

```txt
http://localhost:3001
```

By default it calls the backend at:

```txt
http://localhost:3000
```

To override the API URL:

```bash
NEXT_PUBLIC_API_BASE_URL=http://localhost:3000 npm run admin:dev
```

Google Maps requires a browser API key:

```bash
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=your_google_maps_web_key npm run admin:dev
```

## Test Account

Seed local admin role users with:

```bash
npm run backend:seed:admin
```

Owner test account:

```txt
07701234567
```

The current backend development OTP is:

```txt
123456
```
