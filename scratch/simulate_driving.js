const http = require('https');
const { spawn } = require('child_process');

const deviceId = 'DACBA735-CA10-42F5-83CB-AB92F953A99C';
const stops = [
  { lat: 33.3152, lng: 44.4161 }, // Bab Al-Sharqi
  { lat: 33.3236, lng: 44.3959 }, // Al-Salihiya
  { lat: 33.3601, lng: 44.3656 }, // Al-Atifiya
  { lat: 33.3792, lng: 44.3384 }  // Kadhimiya
];

const coordsString = stops.map(s => `${s.lng},${s.lat}`).join(';');
const url = `https://router.project-osrm.org/route/v1/driving/${coordsString}?overview=full&geometries=geojson`;

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
      console.log(`Loaded ${coordinates.length} waypoints along the driving route.`);
      
      const simctl = spawn('xcrun', [
        'simctl', 'location', deviceId, 'start',
        '--speed=15', // 15 m/s = 54 km/h
        '--interval=2',
        '-'
      ]);

      simctl.stdout.on('data', (d) => console.log(`[simctl]: ${d}`));
      simctl.stderr.on('data', (d) => console.error(`[simctl error]: ${d}`));

      coordinates.forEach(([lng, lat]) => {
        simctl.stdin.write(`${lat},${lng}\n`);
      });
      simctl.stdin.end();

      console.log('Driving simulation started! Press Ctrl+C to stop.');
    } catch (e) {
      console.error('Failed to parse route:', e);
    }
  });
}).on('error', (e) => {
  console.error('OSRM request failed:', e);
});
