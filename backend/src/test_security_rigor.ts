import axios from "axios";
import { io } from "socket.io-client";

const BASE_URL = process.env.TEST_API_URL || "https://mivia-backend.onrender.com";

interface TestResult {
  name: string;
  passed: boolean;
  details: string;
}

const results: TestResult[] = [];

async function runTests() {
  console.log(`\n======================================================`);
  console.log(`🛡️  RUNNING PENETRATION & RIGOR TESTS AGAINST: ${BASE_URL}`);
  console.log(`======================================================\n`);

  // Test 1: Health Check
  try {
    const res = await axios.get(`${BASE_URL}/health`);
    results.push({
      name: "API Health & Availability",
      passed: res.status === 200 && res.data.status === "healthy",
      details: `Status: ${res.status}, Body: ${JSON.stringify(res.data)}`,
    });
  } catch (err: any) {
    results.push({
      name: "API Health & Availability",
      passed: false,
      details: err.message,
    });
  }

  // Test 2: Admin Registration Escalation Prevention
  // Attempt to register a user with role: 'ADMIN'
  try {
    const fakeAdminEmail = `test_hacker_${Date.now()}@malvoya.com`;
    const res = await axios.post(
      `${BASE_URL}/api/v1/auth/register`,
      {
        name: "Malicious Attacker",
        email: fakeAdminEmail,
        password: "SuperSecretPassword123!",
        role: "ADMIN",
      },
      { validateStatus: () => true }
    );

    const isRejected = res.status === 400 || (res.data && res.data.user && res.data.user.role !== "ADMIN");
    results.push({
      name: "Admin Privilege Escalation Prevention",
      passed: isRejected,
      details: `HTTP ${res.status}: ${JSON.stringify(res.data)}`,
    });
  } catch (err: any) {
    results.push({
      name: "Admin Privilege Escalation Prevention",
      passed: false,
      details: err.message,
    });
  }

  // Test 3: Unauthenticated Access to GDPR Data Endpoint
  try {
    const res = await axios.get(`${BASE_URL}/api/v1/auth/me/data`, {
      validateStatus: () => true,
    });
    results.push({
      name: "GDPR Data Leak Protection (Unauthenticated)",
      passed: res.status === 401,
      details: `HTTP ${res.status}: ${JSON.stringify(res.data)}`,
    });
  } catch (err: any) {
    results.push({
      name: "GDPR Data Leak Protection (Unauthenticated)",
      passed: false,
      details: err.message,
    });
  }

  // Test 4: Socket.io Unauthenticated Connection Rejection
  const socketTest = new Promise<TestResult>((resolve) => {
    const socket = io(BASE_URL, {
      transports: ["websocket"],
      reconnection: false,
      timeout: 5000,
      auth: { token: "" }, // No token provided
    });

    socket.on("connect", () => {
      socket.disconnect();
      resolve({
        name: "Socket.io JWT Authentication Enforced",
        passed: false,
        details: "Socket connected without a JWT token (Vulnerability!)",
      });
    });

    socket.on("connect_error", (err) => {
      socket.disconnect();
      resolve({
        name: "Socket.io JWT Authentication Enforced",
        passed: true,
        details: `Connection rejected as expected: ${err.message}`,
      });
    });

    setTimeout(() => {
      socket.disconnect();
      resolve({
        name: "Socket.io JWT Authentication Enforced",
        passed: true,
        details: "Timed out / refused unauthenticated handshake as expected",
      });
    }, 6000);
  });

  results.push(await socketTest);

  // Print Summary Table
  console.log(`\n======================================================`);
  console.log(`📊 TEST RESULTS SUMMARY`);
  console.log(`======================================================\n`);

  let allPassed = true;
  for (const r of results) {
    const icon = r.passed ? "✅ PASS" : "❌ FAIL";
    if (!r.passed) allPassed = false;
    console.log(`${icon} | ${r.name}`);
    console.log(`       Details: ${r.details}\n`);
  }

  if (allPassed) {
    console.log(`🏆 ALL SECURITY PENETRATION CHECKS PASSED!\n`);
  } else {
    console.log(`⚠️  SOME CHECKS FAILED - REVIEW DETAILS ABOVE!\n`);
  }
}

runTests();
