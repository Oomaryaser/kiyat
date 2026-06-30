const http = require('https');
const { spawn } = require('child_process');

// Driver simulator ID (iPhone 17 Pro)
const deviceId = '59B402E7-6155-4028-847D-1DCFFBE43FB4';

// Start: Driver current position
const start = { lat: 33.325, lng: 44.435 };
// Target: First stop of "تيست حقيقي" (Abu Nuwas / Route Start)
const target = { lat: 33.323855194, lng: 44.40931377 };

const url = `https://router.project-osrm.org/route/v1/driving/${start.lng},${start.lat};${target.lng},${target.lat}?overview=full&geometries=geojson`;

console.log('Fetching route from OSRM...');
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
      console.log(`Loaded ${coordinates.length} waypoints along the route to start.`);

      const simctl = spawn('xcrun', [
        'simctl', 'location', deviceId, 'start',
        '--speed=12', // 12 m/s = 43 km/h
        '--interval=1',
        '-'
      ]);

      simctl.stdout.on('data', (d) => console.log(`[simctl]: ${d}`));
      simctl.stderr.on('data', (d) => console.error(`[simctl error]: ${d}`));

      coordinates.forEach(([lng, lat]) => {
        simctl.stdin.write(`${lat},${lng}\n`);
      });
      simctl.stdin.end();

      console.log('🚗 Driver simulation started! Check the iPhone 17 Pro simulator screen.');
      console.log('The driver will follow the real streets towards Abu Nuwas.');
    } catch (e) {
      console.error('Failed to parse route:', e);
    }
  });
}).on('error', (e) => {
  console.error('OSRM request failed:', e);
});
