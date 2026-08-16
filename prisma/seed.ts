import { PrismaClient } from '../generated/prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import * as bcrypt from 'bcrypt';

const ADMIN_SEED_EMAIL = 'admin@kelasxtra.test';
const ADMIN_SEED_PASSWORD = 'admin12345';

async function runSeed() {
  const adapter = new PrismaMariaDb({
    host: 'localhost',
    port: 3306,
    user: 'root',
    password: process.env.DB_PASSWORD || 'qwerty123',
    database: 'education_app',
    connectionLimit: 5,
  });

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

  // Learning Engine Phase 4: harus selalu ada tepat satu config yang active=true.
  // Kalau nanti tim akademik mau tuning formula, insert baris baru dengan
  // configVersion lebih tinggi, matikan yang lama (active=false) — jangan
  // pernah update baris config yang sudah pernah dipakai (supaya snapshot lama
  // tetap bisa ditelusuri formula-nya lewat engineVersion/configVersion).
  const existingActiveConfig = await prisma.learningEngineConfig.findFirst({
    where: { active: true },
  });

  if (!existingActiveConfig) {
    await prisma.learningEngineConfig.create({
      data: {
        alpha: 0.3,
        difficultyEasyWeight: 1.0,
        difficultyMediumWeight: 1.5,
        difficultyHardWeight: 2.0,
        masteredThreshold: 80,
        developingThreshold: 60,
        confidenceK: 5,
        minimumConfidence: 0.6,
        engineVersion: 1,
        configVersion: 1,
        active: true,
      },
    });
    console.log('LearningEngineConfig default (v1) dibuat.');
  } else {
    console.log('LearningEngineConfig active sudah ada, tidak dibuat ulang.');
  }

  await prisma.$disconnect();
}

runSeed().catch((error) => {
  console.error('Gagal menjalankan seed:', error);
  process.exit(1);
});
