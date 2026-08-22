import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { createTestApp } from './utils/test-app.helper';

/**
 * Phase 5 (Security & Integration): Auth sebelumnya TIDAK PUNYA satu pun
 * e2e test, padahal ini modul paling kritikal di seluruh aplikasi dan
 * "Authentication flow" disebut eksplisit di dokumen master section 17.2
 * sebagai bagian wajib Integration Test.
 */
describe('Auth (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    const ctx = await createTestApp();
    app = ctx.app;
    prisma = ctx.prisma;
  });

  afterAll(async () => {
    await app.close();
  });

  function uniqueEmail(prefix: string) {
    return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 100000)}@e2e-test.local`;
  }

  describe('POST /auth/register', () => {
    it('happy path: register STUDENT (default role) -> dapat accessToken + refreshToken', async () => {
      const email = uniqueEmail('reg-student');

      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: 'Student E2E' })
        .expect(201);

      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.refreshToken).toBeDefined();

      const user = await prisma.user.findUniqueOrThrow({ where: { email } });
      expect(user.status).toBe('ACTIVE');
    });

    it('register TEACHER eksplisit -> TeacherProfile.name tersimpan (bukan silent data loss)', async () => {
      const email = uniqueEmail('reg-teacher');

      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: 'Teacher E2E', role: 'TEACHER' })
        .expect(201);

      const user = await prisma.user.findUniqueOrThrow({
        where: { email },
        include: { teacherProfile: true },
      });
      expect(user.teacherProfile?.name).toBe('Teacher E2E');
    });

    it('email sudah terdaftar -> 409, bukan 500 (race condition guard)', async () => {
      const email = uniqueEmail('reg-dup');

      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: 'First' })
        .expect(201);

      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: 'Second' })
        .expect(409);
    });

    it('coba register sebagai ADMIN lewat public endpoint -> ditolak validasi (400)', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email: uniqueEmail('reg-admin'), password: 'password123', name: 'X', role: 'ADMIN' })
        .expect(400);
    });

    it('password kurang dari 6 karakter -> 400', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email: uniqueEmail('reg-short'), password: '123', name: 'X' })
        .expect(400);
    });

    it('email tidak valid -> 400', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email: 'bukan-email', password: 'password123', name: 'X' })
        .expect(400);
    });
  });

  describe('POST /auth/login', () => {
    async function registerFixtureUser(prefix: string) {
      const email = uniqueEmail(prefix);
      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: prefix })
        .expect(201);
      return email;
    }

    it('happy path: email+password benar -> dapat token pair', async () => {
      const email = await registerFixtureUser('login-ok');

      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: 'password123' })
        .expect(200);

      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.refreshToken).toBeDefined();
    });

    it('password salah -> 401 dengan pesan generik (tidak bocorin mana yang salah)', async () => {
      const email = await registerFixtureUser('login-wrongpw');

      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: 'password-salah' })
        .expect(401);

      expect(res.body.message).toBe('Email atau password salah.');
    });

    it('email tidak terdaftar -> 401 dengan pesan GENERIK YANG SAMA (anti email-enumeration)', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: uniqueEmail('login-notexist'), password: 'password123' })
        .expect(401);

      expect(res.body.message).toBe('Email atau password salah.');
    });

    it('account lockout: 5x salah password berturut-turut -> akun terkunci, percobaan ke-6 ditolak walau password BENAR', async () => {
      const email = await registerFixtureUser('login-lockout');

      for (let i = 0; i < 5; i++) {
        await request(app.getHttpServer())
          .post('/api/v1/auth/login')
          .send({ email, password: 'password-salah' })
          .expect(401);
      }

      const user = await prisma.user.findUniqueOrThrow({ where: { email } });
      expect(user.lockedUntil).not.toBeNull();
      expect(user.lockedUntil!.getTime()).toBeGreaterThan(Date.now());

      // Password BENAR pun tetap ditolak selama masih terkunci -- lockout
      // dicek SEBELUM bcrypt.compare (hemat CPU, dan konsisten).
      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: 'password123' })
        .expect(401);
      expect(res.body.message).toContain('terkunci');
    });

    it('akun SUSPENDED -> login ditolak walau password benar', async () => {
      const email = await registerFixtureUser('login-suspended');
      await prisma.user.update({ where: { email }, data: { status: 'SUSPENDED' } });

      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: 'password123' })
        .expect(401);
      expect(res.body.message).toContain('tidak aktif');
    });
  });

  describe('GET /auth/me + enforcement status real-time', () => {
    it('tanpa token -> 401', async () => {
      await request(app.getHttpServer()).get('/api/v1/auth/me').expect(401);
    });

    it('dengan token valid -> data user TANPA password/failedLoginAttempts/lockedUntil', async () => {
      const email = uniqueEmail('me-ok');
      const registerRes = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: 'Me Test' })
        .expect(201);

      const res = await request(app.getHttpServer())
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${registerRes.body.data.accessToken}`)
        .expect(200);

      expect(res.body.data.email).toBe(email);
      expect(res.body.data.password).toBeUndefined();
      expect(res.body.data.failedLoginAttempts).toBeUndefined();
      expect(res.body.data.lockedUntil).toBeUndefined();
    });

    it('SUSPENDED di tengah sesi -> access token yang sudah terbit langsung ditolak (tidak perlu nunggu expire)', async () => {
      const email = uniqueEmail('me-suspended-midsession');
      const registerRes = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: 'Suspend Mid Session' })
        .expect(201);
      const accessToken = registerRes.body.data.accessToken;

      // Token masih fresh & belum expired -- tapi status di-suspend
      // langsung lewat DB (mensimulasikan admin men-suspend akun ini).
      await prisma.user.update({ where: { email }, data: { status: 'SUSPENDED' } });

      await request(app.getHttpServer())
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(401);
    });

    it('token asal-asalan/garbage -> 401', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/auth/me')
        .set('Authorization', 'Bearer ini-bukan-jwt-valid')
        .expect(401);
    });
  });

  describe('POST /auth/refresh + POST /auth/logout', () => {
    async function loginFixtureUser(prefix: string) {
      const email = uniqueEmail(prefix);
      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ email, password: 'password123', name: prefix })
        .expect(201);
      return { email, ...res.body.data };
    }

    it('refresh token valid -> dapat token pair baru, refresh token LAMA tidak bisa dipakai lagi (rotation)', async () => {
      const { refreshToken: oldRefreshToken } = await loginFixtureUser('refresh-rotation');

      const res = await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: oldRefreshToken })
        .expect(200);

      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.refreshToken).not.toBe(oldRefreshToken);

      // Refresh token lama sudah di-revoke -- dipakai lagi harus ditolak.
      await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: oldRefreshToken })
        .expect(401);
    });

    it('refresh token garbage/invalid -> 401', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: 'bukan-token-valid' })
        .expect(401);
    });

    it('logout mencabut refresh token -> tidak bisa dipakai refresh lagi setelahnya', async () => {
      const { refreshToken } = await loginFixtureUser('logout-revoke');

      await request(app.getHttpServer())
        .post('/api/v1/auth/logout')
        .send({ refreshToken })
        .expect(200);

      await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken })
        .expect(401);
    });
  });
});
