const BASE_URL = process.env.TEST_API_URL || "https://mivia-backend.onrender.com";

async function runTests() {
  console.log(`\n======================================================`);
  console.log(`🛡️  RUNNING PENETRATION & RIGOR TESTS AGAINST: ${BASE_URL}`);
  console.log(`======================================================\n`);

  const results = [];

  // Test 1: Health Check
  try {
    const res = await fetch(`${BASE_URL}/health`);
    const data = await res.json();
    results.push({
      name: "API Health & Availability",
      passed: res.status === 200 && data.status === "healthy",
      details: `HTTP ${res.status}: ${JSON.stringify(data)}`,
    });
  } catch (err) {
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
    const res = await fetch(`${BASE_URL}/api/v1/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "Malicious Attacker",
        email: fakeAdminEmail,
        password: "SuperSecretPassword123!",
        role: "ADMIN",
      }),
    });
    const data = await res.json().catch(() => ({}));
    // Zod schema rejected 'ADMIN' -> status 400 Bad Request
    const isRejected = res.status === 400 || (data.user && data.user.role !== "ADMIN");
    results.push({
      name: "Admin Privilege Escalation Prevention",
      passed: isRejected,
      details: `HTTP ${res.status}: ${JSON.stringify(data)}`,
    });
  } catch (err) {
    results.push({
      name: "Admin Privilege Escalation Prevention",
      passed: false,
      details: err.message,
    });
  }

  // Test 3: Unauthenticated Access to GDPR Data Endpoint
  try {
    const res = await fetch(`${BASE_URL}/api/v1/auth/me/data`);
    const data = await res.json().catch(() => ({}));
    results.push({
      name: "GDPR Data Leak Protection (Unauthenticated)",
      passed: res.status === 401,
      details: `HTTP ${res.status}: ${JSON.stringify(data)}`,
    });
  } catch (err) {
    results.push({
      name: "GDPR Data Leak Protection (Unauthenticated)",
      passed: false,
      details: err.message,
    });
  }

  // Test 4: Unauthenticated Access to GDPR Account Deletion Endpoint
  try {
    const res = await fetch(`${BASE_URL}/api/v1/auth/me`, { method: "DELETE" });
    const data = await res.json().catch(() => ({}));
    results.push({
      name: "GDPR Account Deletion Protection (Unauthenticated)",
      passed: res.status === 401,
      details: `HTTP ${res.status}: ${JSON.stringify(data)}`,
    });
  } catch (err) {
    results.push({
      name: "GDPR Account Deletion Protection (Unauthenticated)",
      passed: false,
      details: err.message,
    });
  }

  // Test 5: Verify Courier Status Update Injection Validation
  try {
    const res = await fetch(`${BASE_URL}/api/v1/orders/courier/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        status: "INVALID_INVENTED_STATUS",
        lat: "not-a-number",
      }),
    });
    const data = await res.json().catch(() => ({}));
    // Should fail with 401 (needs auth) or 400 (invalid schema)
    results.push({
      name: "Courier Telemetry Injection Protection",
      passed: res.status === 401 || res.status === 400,
      details: `HTTP ${res.status}: ${JSON.stringify(data)}`,
    });
  } catch (err) {
    results.push({
      name: "Courier Telemetry Injection Protection",
      passed: false,
      details: err.message,
    });
  }

  // Summary
  console.log(`\n======================================================`);
  console.log(`📊 LIVE SECURITY PROBE RESULTS`);
  console.log(`======================================================\n`);

  let allPassed = true;
  for (const r of results) {
    const icon = r.passed ? "✅ PASS" : "❌ FAIL";
    if (!r.passed) allPassed = false;
    console.log(`${icon} | ${r.name}`);
    console.log(`       Details: ${r.details}\n`);
  }

  if (allPassed) {
    console.log(`🏆 ALL TESTED SECURITY GATES ARE ACTIVELY ENFORCING PROTECTION IN PRODUCTION!\n`);
  } else {
    console.log(`⚠️  SOME CHECKS FAILED - REVIEW DETAILS ABOVE!\n`);
  }
}

runTests();
