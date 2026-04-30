/**
 * Run this script once to create your Admin account in the database.
 * Usage: node create-admin.js
 * 
 * Replace the email/password below with your own before running.
 */

const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

async function main() {
  // ── CHANGE THESE TO YOUR DETAILS ──────────────────────────────────────────
  const ADMIN_NAME = 'Malvoya Admin';
  const ADMIN_EMAIL = 'zuheymohamed6789@gmail.com'; // ← PUT YOUR GMAIL HERE
  const ADMIN_PASSWORD = 'JanuaryJanuary2026'; // ← SET A STRONG PASSWORD
  // ──────────────────────────────────────────────────────────────────────────

  const existing = await prisma.user.findUnique({ where: { email: ADMIN_EMAIL } });

  if (existing) {
    if (existing.role === 'ADMIN') {
      console.log(`✅ Admin already exists: ${existing.email}`);
    } else {
      // Upgrade existing user to admin
      await prisma.user.update({ where: { email: ADMIN_EMAIL }, data: { role: 'ADMIN' } });
      console.log(`✅ Upgraded ${ADMIN_EMAIL} to ADMIN role.`);
    }
    return;
  }

  const passwordHash = await bcrypt.hash(ADMIN_PASSWORD, 12);
  const admin = await prisma.user.create({
    data: {
      name: ADMIN_NAME,
      email: ADMIN_EMAIL,
      passwordHash: passwordHash,
      role: 'ADMIN',
    },
  });

  console.log(`\n🎉 Admin account created successfully!`);
  console.log(`   Name:  ${admin.name}`);
  console.log(`   Email: ${admin.email}`);
  console.log(`   Role:  ${admin.role}`);
  console.log(`\n👉 You can now log in at: http://localhost:5174`);
}

main()
  .catch(e => { console.error('❌ Error:', e.message); process.exit(1); })
  .finally(() => prisma.$disconnect());
