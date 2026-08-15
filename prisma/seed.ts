import 'dotenv/config';
import { PrismaClient } from '../generated/prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import * as bcrypt from 'bcrypt';

const ADMIN_SEED_EMAIL = 'admin@kelasxtra.test';
const ADMIN_SEED_PASSWORD = 'admin12345';

async function runSeed() {
  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    throw new Error(
      'DATABASE_URL belum di-set di .env. Seed tidak boleh fallback ke kredensial hardcoded.',
    );
  }

  const adapter = new PrismaMariaDb(databaseUrl);
  const prisma = new PrismaClient({ adapter });

  // TEACHER sempat ketinggalan dari list ini sebelumnya — itu penyebab
  // register role TEACHER gagal sampai dibuat manual lewat script terpisah.
  // Sekarang semua role yang dipakai di codebase (register + RBAC) sudah lengkap di sini.
  const roleNames = [
    'STUDENT',
    'TEACHER',
    'ADMIN',
    'PARENT',
    'TUTOR',
    'PROFESSIONAL',
  ];

  for (const roleName of roleNames) {
    await prisma.role.upsert({
      where: { name: roleName },
      update: {},
      create: { name: roleName },
    });
    console.log(`Role "${roleName}" siap.`);
  }

  // Belum ada endpoint publik untuk membuat akun ADMIN (memang sengaja,
  // demi keamanan), jadi satu akun admin awal disiapkan lewat seed ini
  // supaya endpoint admin-only (CRUD subjects/topics/competencies, dst.) bisa dites.
  const adminRole = await prisma.role.findUniqueOrThrow({
    where: { name: 'ADMIN' },
  });
  const existingAdmin = await prisma.user.findUnique({
    where: { email: ADMIN_SEED_EMAIL },
  });

  if (!existingAdmin) {
    const hashedPassword = await bcrypt.hash(ADMIN_SEED_PASSWORD, 10);
    await prisma.user.create({
      data: {
        email: ADMIN_SEED_EMAIL,
        password: hashedPassword,
        roleId: adminRole.id,
      },
    });
    console.log(
      `Akun ADMIN dibuat: ${ADMIN_SEED_EMAIL} / ${ADMIN_SEED_PASSWORD}`,
    );
  } else {
    console.log('Akun ADMIN seed sudah ada, tidak dibuat ulang.');
  }

  await prisma.$disconnect();
}

runSeed().catch((error) => {
  console.error('Gagal menjalankan seed:', error);
  process.exit(1);
});
