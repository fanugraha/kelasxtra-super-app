import { PrismaClient } from '../generated/prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';

async function runSeed() {
  const adapter = new PrismaMariaDb({
    host: 'localhost',
    port: 3306,
    user: 'root',
    password: 'qwerty123',
    database: 'education_app',
    connectionLimit: 5,
  });

  const prisma = new PrismaClient({ adapter });

  const roleNames = ['STUDENT', 'ADMIN', 'PARENT', 'TUTOR', 'PROFESSIONAL'];

  for (const roleName of roleNames) {
    await prisma.role.upsert({
      where: { name: roleName },
      update: {},
      create: { name: roleName },
    });
    console.log(`Role "${roleName}" siap.`);
  }

  await prisma.$disconnect();
}

runSeed().catch((error) => {
  console.error('Gagal menjalankan seed:', error);
  process.exit(1);
});
