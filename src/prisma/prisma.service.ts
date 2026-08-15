import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '../../generated/prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const databaseUrl = process.env.DATABASE_URL;

    if (!databaseUrl) {
      // Sengaja tidak fallback ke host/user/database hardcoded — begitu
      // deploy ke server lain, koneksi harus jelas gagal saat startup
      // (bukan diam-diam connect ke localhost/root/education_app).
      throw new Error(
        'DATABASE_URL belum di-set di .env. Aplikasi tidak boleh fallback ke kredensial database hardcoded.',
      );
    }

    // Satu-satunya sumber koneksi, sama persis dengan yang dipakai
    // prisma.config.ts untuk migration & seed — tidak ada lagi dua jalur
    // koneksi yang bisa diam-diam beda antara migrate-time dan runtime.
    const adapter = new PrismaMariaDb(databaseUrl);

    super({ adapter });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
