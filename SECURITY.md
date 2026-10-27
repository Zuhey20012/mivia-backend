# Security policy

Malvoya is a pre-launch marketplace for Finland (customer, store and courier apps, an API and an admin panel).
We take reports seriously and answer in English or Finnish.

## Reporting a vulnerability

- Use **Report a vulnerability** on this repository's *Security* tab (GitHub private vulnerability reporting), or
  the contact listed at `https://malvoya-api-eu.onrender.com/.well-known/security.txt`.
- Please do not open a public issue for a vulnerability.
- Include what you found, how to reproduce it and what an attacker could do with it.

We acknowledge reports within 3 working days and tell you what we will do and when.

## Rules for testing

- Use only accounts you created yourself. Never access, change or delete other people's data, orders or money.
- Payments run in Stripe test mode; do not try to move real money or attack Stripe, Firebase, Cloudinary or Render.
- No denial of service, spam, social engineering or physical attacks.
- Stop and report as soon as you can show the problem.

## In scope

- The API (`backend/`) and the admin panel (`malvoya_admin/`)
- The Android apps `com.malvoya.customer`, `com.malvoya.vendor` and `com.malvoya.courier`

Old folders (`mivia_*`, `functions/`) are unused and out of scope.
