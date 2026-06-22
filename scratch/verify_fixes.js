const { io } = require("socket.io-client");
const axios = require("axios");
const jwt = require("jsonwebtoken");

const API_URL = "http://localhost:3000";
const WS_URL = "http://localhost:3000/tracking";
const JWT_SECRET = "e798031d279cf44e59048c1e285a81e35a9bd09b69b5961d15df9efcb33a699c";

async function runTests() {
  console.log("🚀 Starting Verification Tests...");

  // Generate tokens
  const validToken = jwt.sign(
    { sub: "driver-id-123", phone: "+9647701234567", role: "operator" },
    JWT_SECRET,
    { expiresIn: "10m" }
  );

  const expiredToken = jwt.sign(
    { sub: "driver-id-123", phone: "+9647701234567", role: "operator" },
    JWT_SECRET,
    { expiresIn: "-10s" } // already expired
  );

  let waitId = "";
  const anonymousSessionId = "passenger-123456789";

  // Test 1: Start a passenger wait session (REST API)
  try {
    console.log("\n1. Testing passenger wait creation...");
    const routesRes = await axios.get(`${API_URL}/routes`);
    const routeId = routesRes.data.data[0].id;
    console.log(`Using dynamically fetched route ID: ${routeId}`);

    const res = await axios.post(`${API_URL}/tracking/routes/${routeId}/passenger-waits`, {
      anonymousSessionId,
      lat: 33.3152,
      lng: 44.4161,
    });
    waitId = res.data.id;
    console.log(`✅ Created wait session. waitId: ${waitId}`);
  } catch (err) {
    console.error("❌ Failed to create passenger wait:", err.message);
    process.exit(1);
  }

  // Test 2: Attempt cancel without header (Expect 403)
  try {
    console.log("\n2. Testing cancel without x-anonymous-session-id header...");
    await axios.post(`${API_URL}/tracking/passenger-waits/${waitId}/cancel`);
    console.error("❌ Error: Expected 403 Forbidden, but request succeeded!");
    process.exit(1);
  } catch (err) {
    if (err.response && err.response.status === 403) {
      console.log("✅ Correctly rejected with 403 Forbidden!");
    } else {
      console.error("❌ Unexpected response:", err.response ? err.response.status : err.message);
      process.exit(1);
    }
  }

  // Test 3: Attempt cancel with incorrect header (Expect 403)
  try {
    console.log("\n3. Testing cancel with incorrect x-anonymous-session-id header...");
    await axios.post(
      `${API_URL}/tracking/passenger-waits/${waitId}/cancel`,
      {},
      { headers: { "x-anonymous-session-id": "passenger-wrong-id" } }
    );
    console.error("❌ Error: Expected 403 Forbidden, but request succeeded!");
    process.exit(1);
  } catch (err) {
    if (err.response && err.response.status === 403) {
      console.log("✅ Correctly rejected with 403 Forbidden!");
    } else {
      console.error("❌ Unexpected response:", err.response ? err.response.status : err.message);
      process.exit(1);
    }
  }

  // Test 4: Attempt cancel with CORRECT header (Expect 201/200)
  try {
    console.log("\n4. Testing cancel with correct x-anonymous-session-id header...");
    const res = await axios.post(
      `${API_URL}/tracking/passenger-waits/${waitId}/cancel`,
      {},
      { headers: { "x-anonymous-session-id": anonymousSessionId } }
    );
    if (res.data.status === "cancelled") {
      console.log("✅ Successfully cancelled!");
    } else {
      console.error("❌ Cancel response state mismatch:", res.data);
      process.exit(1);
    }
  } catch (err) {
    console.error("❌ Cancel request failed:", err.response ? err.response.data : err.message);
    process.exit(1);
  }

  // Test 5: WebSocket Connection with expired token
  console.log("\n5. Testing WebSocket connection with expired token...");
  const socketExpired = io(WS_URL, {
    transports: ["websocket"],
    auth: { token: `Bearer ${expiredToken}` },
    autoConnect: false,
  });

  socketExpired.connect();
  let expiredDisconnectHandled = false;

  await new Promise((resolve) => {
    socketExpired.on("connect", () => {
      setTimeout(() => {
        if (socketExpired.connected) {
          console.error("❌ Error: Expired token successfully connected and stayed connected!");
          socketExpired.disconnect();
          process.exit(1);
        } else {
          console.log("✅ Expired token connected but was immediately disconnected by the server.");
          expiredDisconnectHandled = true;
          resolve();
        }
      }, 500);
    });

    socketExpired.on("connect_error", (err) => {
      console.log(`✅ Expired token connection rejected (connect_error): ${err.message}`);
      expiredDisconnectHandled = true;
      resolve();
    });

    socketExpired.on("disconnect", (reason) => {
      console.log(`✅ Expired token connection disconnected. Reason: ${reason}`);
      expiredDisconnectHandled = true;
      resolve();
    });

    setTimeout(() => {
      if (!expiredDisconnectHandled) {
        console.log("✅ WebSocket connection rejected (timeout on connect).");
      }
      resolve();
    }, 2000);
  });

  // Test 6: WebSocket token:update with expired token
  console.log("\n6. Testing WebSocket token update with expired token...");
  const socketValid = io(WS_URL, {
    transports: ["websocket"],
    auth: { token: `Bearer ${validToken}` },
    autoConnect: false,
  });

  socketValid.connect();

  await new Promise((resolve) => {
    socketValid.on("connect", () => {
      console.log("✅ WebSocket connected with valid token. Sending expired token update...");
      socketValid.emit("token:update", { token: expiredToken });
    });

    socketValid.on("disconnect", (reason) => {
      console.log(`✅ WebSocket disconnected after sending expired token. Reason: ${reason}`);
      resolve();
    });

    setTimeout(() => {
      console.error("❌ Error: Socket did not disconnect after sending expired token!");
      socketValid.disconnect();
      process.exit(1);
    }, 4000);
  });

  console.log("\n🎉 All Verification Tests Passed Successfully!");
  process.exit(0);
}

runTests().catch((err) => {
  console.error("Test execution failed:", err);
  process.exit(1);
});
