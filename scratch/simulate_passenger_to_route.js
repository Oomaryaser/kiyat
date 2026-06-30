const http = require('https');
const { spawn } = require('child_process');

// Passenger simulator ID (Kiyat iPhone)
const deviceId = 'DACBA735-CA10-42F5-83CB-AB92F953A99C';

// Start: Passenger current position
const start = { lat: 33.3150, lng: 44.4250 };
// Target: Nearest stop on "تيست حقيقي" (Stop 2 / End Stop)
const target = { lat: 33.30872132, lng: 44.42055759 };

const url = `https://router.project-osrm.org/route/v1/driving/${start.lng},${start.lat};${target.lng},${target.lat}?overview=full&geometries=geojson`;

console.log('Fetching route from OSRM for Passenger...');
http.get(url, (res) => {
  let body = '';
  res.on('data', chunk => body += chunk);
  res.on('end', () => {
    try {
      const data = JSON.parse(body);
      if (!data.routes || data.routes.length === 0) {
        console.error('No routes returned from OSRM');
        return;
      }
      const coordinates = data.routes[0].geometry.coordinates; // [lng, lat]
      console.log(`Loaded ${coordinates.length} waypoints along the route to nearest stop.`);

      const simctl = spawn('xcrun', [
        'simctl', 'location', deviceId, 'start',
        '--speed=6', // 6 m/s = 21 km/h (walking/slow driving pace)
        '--interval=1',
        '-'
      ]);

      simctl.stdout.on('data', (d) => console.log(`[simctl]: ${d}`));
      simctl.stderr.on('data', (d) => console.error(`[simctl error]: ${d}`));

      coordinates.forEach(([lng, lat]) => {
        simctl.stdin.write(`${lat},${lng}\n`);
      });
      simctl.stdin.end();

      console.log('🚶 Passenger simulation started! Check the Kiyat iPhone simulator screen.');
      console.log('The passenger will move towards the nearest boarding stop.');
    } catch (e) {
      console.error('Failed to parse route:', e);
    }
  });
}).on('error', (e) => {
  console.error('OSRM request failed:', e);
});
