#!/bin/bash
set -e
echo ">> Phase 5: e2e test Auth (nol coverage sebelumnya) + ownership security Content (Course/Lesson/Material) + ownership & validasi Question Bank/Questions, plus unit test lockout logic di AuthService."

mkdir -p "$(dirname "test/auth.e2e-spec.ts")"
echo ">> Menulis test/auth.e2e-spec.ts"
cat > test/auth.e2e-spec.ts << 'KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026'
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
KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026

mkdir -p "$(dirname "test/content-ownership.e2e-spec.ts")"
echo ">> Menulis test/content-ownership.e2e-spec.ts"
cat > test/content-ownership.e2e-spec.ts << 'KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026'
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { createTestApp, registerStudent, registerTeacher } from './utils/test-app.helper';

/**
 * Phase 5 (Security): section 17.3 dokumen master eksplisit minta
 * "Teacher tidak dapat mengubah content milik teacher lain tanpa
 * permission" -- kode ownership check-nya SUDAH ADA sejak awal
 * (ForbiddenException di Courses/Lessons/MaterialsService), tapi
 * sebelum ini TIDAK ADA satu test pun yang membuktikannya. Ini persis
 * kelas bug yang bikin diagnostics.service.ts kehilangan fitur secara
 * diam-diam beberapa kali -- kode tanpa test itu rapuh.
 */
describe('Content ownership security (Course -> Lesson -> Material) (e2e)', () => {
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

  async function createSubject() {
    const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    return prisma.subject.create({
      data: { code: `E2E-CONTENT-${suffix}`, name: 'E2E Content Subject' },
    });
  }

  describe('RBAC: hanya TEACHER yang boleh membuat content', () => {
    it('STUDENT coba bikin course -> 403', async () => {
      const student = await registerStudent(app, 'content-rbac-student');
      const subject = await createSubject();

      await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ subjectId: subject.id, title: 'Percobaan Siswa' })
        .expect(403);
    });
  });

  describe('ownership: TEACHER lain tidak bisa ubah course/lesson/material milik TEACHER ini', () => {
    it('full chain: course, lesson, dan material -> semuanya ditolak (403) untuk teacher B', async () => {
      const teacherA = await registerTeacher(app, 'content-owner-a');
      const teacherB = await registerTeacher(app, 'content-intruder-b');
      const subject = await createSubject();

      // Teacher A bikin course -> lesson -> material, rantai lengkap.
      const courseRes = await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ subjectId: subject.id, title: 'Course milik A' })
        .expect(201);
      const courseId = courseRes.body.data.id;

      const lessonRes = await request(app.getHttpServer())
        .post('/api/v1/lessons')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ courseId, title: 'Lesson milik A' })
        .expect(201);
      const lessonId = lessonRes.body.data.id;

      const materialRes = await request(app.getHttpServer())
        .post('/api/v1/materials')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ lessonId, title: 'Materi milik A', type: 'TEXT', content: 'isi materi' })
        .expect(201);
      const materialId = materialRes.body.data.id;

      // Teacher B coba UPDATE ketiganya -> semua harus 403.
      await request(app.getHttpServer())
        .put(`/api/v1/courses/${courseId}`)
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ title: 'Diubah paksa oleh B' })
        .expect(403);

      await request(app.getHttpServer())
        .put(`/api/v1/lessons/${lessonId}`)
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ title: 'Diubah paksa oleh B' })
        .expect(403);

      await request(app.getHttpServer())
        .put(`/api/v1/materials/${materialId}`)
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ title: 'Diubah paksa oleh B' })
        .expect(403);

      // Teacher B juga tidak bisa numpang nambah lesson/material BARU
      // di course/lesson milik A.
      await request(app.getHttpServer())
        .post('/api/v1/lessons')
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ courseId, title: 'Lesson nyelonong dari B' })
        .expect(403);

      await request(app.getHttpServer())
        .post('/api/v1/materials')
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ lessonId, title: 'Materi nyelonong dari B', type: 'TEXT' })
        .expect(403);

      // Sanity check: data ASLI tidak berubah sama sekali gara-gara
      // percobaan B di atas.
      const course = await prisma.course.findUniqueOrThrow({ where: { id: courseId } });
      expect(course.title).toBe('Course milik A');
    });

    it('teacher A tetap bisa update miliknya sendiri (positive case, bukan cuma negative)', async () => {
      const teacherA = await registerTeacher(app, 'content-owner-positive');
      const subject = await createSubject();

      const courseRes = await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ subjectId: subject.id, title: 'Judul awal' })
        .expect(201);

      const updateRes = await request(app.getHttpServer())
        .put(`/api/v1/courses/${courseRes.body.data.id}`)
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ title: 'Judul sudah direvisi' })
        .expect(200);

      expect(updateRes.body.data.title).toBe('Judul sudah direvisi');
    });
  });

  describe('visibility: course DRAFT default tidak muncul di listing publik', () => {
    it('course baru (DRAFT default) tidak ikut ke GET /courses tanpa filter status', async () => {
      const teacher = await registerTeacher(app, 'content-visibility');
      const subject = await createSubject();

      const courseRes = await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ subjectId: subject.id, title: 'Course draft tersembunyi' })
        .expect(201);

      const listRes = await request(app.getHttpServer())
        .get('/api/v1/courses')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(200);

      const found = listRes.body.data.find((c: { id: number }) => c.id === courseRes.body.data.id);
      expect(found).toBeUndefined();

      // Tapi tetap ketemu kalau filter status eksplisit diminta.
      const draftListRes = await request(app.getHttpServer())
        .get('/api/v1/courses?status=DRAFT')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(200);
      const foundDraft = draftListRes.body.data.find(
        (c: { id: number }) => c.id === courseRes.body.data.id,
      );
      expect(foundDraft).toBeDefined();
    });
  });
});
KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026

mkdir -p "$(dirname "test/question-banks.e2e-spec.ts")"
echo ">> Menulis test/question-banks.e2e-spec.ts"
cat > test/question-banks.e2e-spec.ts << 'KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026'
import { INestApplication } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { createTestApp, registerStudent, registerTeacher } from './utils/test-app.helper';

/**
 * Phase 5 (Security): sama semangatnya dengan content-ownership.e2e-spec.ts
 * -- QuestionBanksService/QuestionsService punya ownership check
 * (ensureCanEditBank) sejak awal ditulis, tapi belum pernah dibuktikan
 * lewat test. Juga menutup celah: soal pilihan ganda dengan jumlah
 * jawaban benar yang salah (0 atau >1) tidak bisa dinilai benar oleh
 * EvidenceAggregator (fix Bug #1) -- makanya validasi ini penting dijaga.
 */
describe('Question Banks & Questions ownership + validation (e2e)', () => {
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

  async function createSubject() {
    const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    return prisma.subject.create({
      data: { code: `E2E-QB-${suffix}`, name: 'E2E QuestionBank Subject' },
    });
  }

  // Tidak ada jalur publik untuk register ADMIN (memang sengaja) -- buat
  // langsung lewat Prisma seperti pola createAssessmentFixture, lalu login
  // via API supaya dapat token asli (bukan token yang dipalsu manual).
  async function registerAdmin(prefix: string) {
    const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    const email = `${prefix}-${suffix}@e2e-test.local`;
    const password = 'password123';

    const adminRole = await prisma.role.findUniqueOrThrow({ where: { name: 'ADMIN' } });
    await prisma.user.create({
      data: {
        email,
        password: await bcrypt.hash(password, 10),
        roleId: adminRole.id,
      },
    });

    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password })
      .expect(200);

    return { accessToken: res.body.data.accessToken as string };
  }

  describe('ownership: TEACHER lain tidak bisa nambah soal ke bank TEACHER ini', () => {
    it('bank milik teacher A -> teacher B nambah soal -> 403', async () => {
      const teacherA = await registerTeacher(app, 'qb-owner-a');
      const teacherB = await registerTeacher(app, 'qb-intruder-b');
      const subject = await createSubject();

      const bankRes = await request(app.getHttpServer())
        .post('/api/v1/question-banks')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ subjectId: subject.id, name: 'Bank milik A' })
        .expect(201);

      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({
          questionBankId: bankRes.body.data.id,
          questionText: 'Soal nyelonong dari B',
          options: [
            { optionText: 'A', isCorrect: true },
            { optionText: 'B', isCorrect: false },
          ],
        })
        .expect(403);
    });
  });

  describe('ownership: bank platform-wide (ADMIN) tidak bisa disentuh TEACHER', () => {
    it('ADMIN bikin bank platform-wide -> TEACHER manapun nambah soal -> 403, ADMIN sendiri -> 201', async () => {
      const admin = await registerAdmin('qb-admin');
      const teacher = await registerTeacher(app, 'qb-teacher-vs-platform');
      const subject = await createSubject();

      const bankRes = await request(app.getHttpServer())
        .post('/api/v1/question-banks')
        .set('Authorization', `Bearer ${admin.accessToken}`)
        .send({ subjectId: subject.id, name: 'Bank platform-wide' })
        .expect(201);

      const bank = await prisma.questionBank.findUniqueOrThrow({
        where: { id: bankRes.body.data.id },
      });
      expect(bank.teacherId).toBeNull();

      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({
          questionBankId: bankRes.body.data.id,
          questionText: 'Teacher coba nambah ke bank platform',
          options: [
            { optionText: 'A', isCorrect: true },
            { optionText: 'B', isCorrect: false },
          ],
        })
        .expect(403);

      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${admin.accessToken}`)
        .send({
          questionBankId: bankRes.body.data.id,
          questionText: 'Admin boleh nambah ke bank sendiri',
          options: [
            { optionText: 'A', isCorrect: true },
            { optionText: 'B', isCorrect: false },
          ],
        })
        .expect(201);
    });
  });

  describe('validasi: pilihan ganda wajib >=2 opsi dengan TEPAT SATU yang benar', () => {
    let teacherToken: string;
    let bankId: number;

    beforeAll(async () => {
      const teacher = await registerTeacher(app, 'qb-validation');
      const subject = await createSubject();
      teacherToken = teacher.accessToken;

      const bankRes = await request(app.getHttpServer())
        .post('/api/v1/question-banks')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({ subjectId: subject.id, name: 'Bank validasi' })
        .expect(201);
      bankId = bankRes.body.data.id;
    });

    it('cuma 1 opsi -> 400', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({
          questionBankId: bankId,
          questionText: 'Soal dengan 1 opsi',
          options: [{ optionText: 'Satu-satunya', isCorrect: true }],
        })
        .expect(400);
    });

    it('nol opsi yang benar -> 400', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({
          questionBankId: bankId,
          questionText: 'Soal tanpa jawaban benar',
          options: [
            { optionText: 'A', isCorrect: false },
            { optionText: 'B', isCorrect: false },
          ],
        })
        .expect(400);
    });

    it('lebih dari 1 opsi yang benar -> 400', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({
          questionBankId: bankId,
          questionText: 'Soal dengan 2 jawaban benar',
          options: [
            { optionText: 'A', isCorrect: true },
            { optionText: 'B', isCorrect: true },
          ],
        })
        .expect(400);
    });

    it('tepat 1 opsi benar dari >=2 -> 201', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({
          questionBankId: bankId,
          questionText: 'Soal valid',
          options: [
            { optionText: 'A', isCorrect: true },
            { optionText: 'B', isCorrect: false },
            { optionText: 'C', isCorrect: false },
          ],
        })
        .expect(201);

      expect(res.body.data.options).toHaveLength(3);
    });

    it('ESSAY tanpa options sama sekali -> tetap 201 (aturan MC/TF tidak berlaku)', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({
          questionBankId: bankId,
          questionText: 'Jelaskan proses fotosintesis.',
          questionType: 'ESSAY',
        })
        .expect(201);
    });

    it('opsi jawaban TIDAK BISA diedit lewat update (integritas soal yang sudah pernah dipakai)', async () => {
      const createRes = await request(app.getHttpServer())
        .post('/api/v1/questions')
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({
          questionBankId: bankId,
          questionText: 'Soal untuk dites update',
          options: [
            { optionText: 'A', isCorrect: true },
            { optionText: 'B', isCorrect: false },
          ],
        })
        .expect(201);

      const updateRes = await request(app.getHttpServer())
        .put(`/api/v1/questions/${createRes.body.data.id}`)
        .set('Authorization', `Bearer ${teacherToken}`)
        .send({ questionText: 'Teks direvisi', options: [{ optionText: 'Coba nyelipin', isCorrect: true }] })
        .expect(200);

      // UpdateQuestionDto sengaja tidak punya field `options` -- field
      // asing di-strip oleh ValidationPipe whitelist, jadi opsi lama
      // tetap utuh walau dikirim di body.
      expect(updateRes.body.data.questionText).toBe('Teks direvisi');
      expect(updateRes.body.data.options).toHaveLength(2);
    });
  });

  describe('RBAC: STUDENT tidak boleh akses /questions sama sekali', () => {
    it('STUDENT GET /questions -> 403', async () => {
      const student = await registerStudent(app, 'qb-rbac-student');

      await request(app.getHttpServer())
        .get('/api/v1/questions')
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(403);
    });
  });
});
KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026

mkdir -p "$(dirname "src/auth/auth.service.spec.ts")"
echo ">> Menulis src/auth/auth.service.spec.ts"
cat > src/auth/auth.service.spec.ts << 'KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026'
import { Test, TestingModule } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { UsersService } from '../users/users.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditLogService } from '../common/services/audit-log.service';

describe('AuthService', () => {
  let service: AuthService;

  const mockUsersService = {
    findUserByEmail: jest.fn(),
    findUserById: jest.fn(),
    createStudentUser: jest.fn(),
    createTeacherUser: jest.fn(),
  };

  const mockJwtService = {
    signAsync: jest.fn().mockResolvedValue('signed.jwt.token'),
    verifyAsync: jest.fn(),
  };

  const mockPrismaService = {
    user: {
      update: jest.fn(),
    },
    refreshToken: {
      create: jest.fn().mockResolvedValue({}),
      update: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
    },
  };

  const mockAuditLogService = {
    record: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    mockJwtService.signAsync.mockResolvedValue('signed.jwt.token');
    mockPrismaService.refreshToken.create.mockResolvedValue({});

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: UsersService, useValue: mockUsersService },
        { provide: JwtService, useValue: mockJwtService },
        { provide: PrismaService, useValue: mockPrismaService },
        { provide: AuditLogService, useValue: mockAuditLogService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // Section 17.1 dokumen master: "Authentication" wajib masuk Unit Test.
  // Sebelum ini file cuma smoke test ("should be defined") -- tidak
  // menguji satupun logic keputusan security (lockout, status
  // enforcement) yang sebenarnya jadi inti modul ini.
  describe('loginWithEmailPassword', () => {
    const REAL_PASSWORD_HASH = bcrypt.hashSync('password123', 4); // rounds rendah -- cukup buat test, tidak perlu lambat

    function buildMockUser(overrides: Record<string, unknown> = {}) {
      return {
        id: 1,
        email: 'user@test.local',
        password: REAL_PASSWORD_HASH,
        status: 'ACTIVE',
        failedLoginAttempts: 0,
        lockedUntil: null,
        role: { name: 'STUDENT' },
        ...overrides,
      };
    }

    it('email tidak ditemukan -> UnauthorizedException dengan pesan generik', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(null);

      await expect(
        service.loginWithEmailPassword({ email: 'ga-ada@test.local', password: 'apapun' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('status bukan ACTIVE -> ditolak SEBELUM sempat bcrypt.compare (hemat CPU)', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ status: 'SUSPENDED' }));
      const compareSpy = jest.spyOn(bcrypt, 'compare');

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password123' }),
      ).rejects.toThrow('Akun tidak aktif. Hubungi admin.');

      expect(compareSpy).not.toHaveBeenCalled();
      compareSpy.mockRestore();
    });

    it('lockedUntil di masa depan -> ditolak SEBELUM sempat bcrypt.compare', async () => {
      const future = new Date(Date.now() + 10 * 60_000);
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ lockedUntil: future }));
      const compareSpy = jest.spyOn(bcrypt, 'compare');

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password123' }),
      ).rejects.toThrow(/terkunci/);

      expect(compareSpy).not.toHaveBeenCalled();
      compareSpy.mockRestore();
    });

    it('password salah -> increment failedLoginAttempts, BELUM mengunci kalau masih di bawah 5', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ failedLoginAttempts: 2 }));

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password-salah' }),
      ).rejects.toThrow('Email atau password salah.');

      expect(mockPrismaService.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { failedLoginAttempts: 3 },
      });
    });

    it('password salah pada percobaan ke-5 -> akun dikunci (lockedUntil di-set)', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ failedLoginAttempts: 4 }));

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password-salah' }),
      ).rejects.toThrow('Email atau password salah.');

      expect(mockPrismaService.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { failedLoginAttempts: 5, lockedUntil: expect.any(Date) },
      });
      expect(mockAuditLogService.record).toHaveBeenCalledWith(
        'ACCOUNT_LOCKED',
        1,
        expect.objectContaining({ untilIso: expect.any(String) }),
      );
    });

    it('password benar & akun bersih -> sukses, TIDAK memanggil reset counter (sudah 0)', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser());

      const result = await service.loginWithEmailPassword({
        email: 'user@test.local',
        password: 'password123',
      });

      expect(result.accessToken).toBe('signed.jwt.token');
      expect(mockPrismaService.user.update).not.toHaveBeenCalled();
      expect(mockAuditLogService.record).toHaveBeenCalledWith(
        'LOGIN_SUCCESS',
        1,
        expect.any(Object),
      );
    });

    it('password benar setelah sempat gagal beberapa kali -> reset failedLoginAttempts & lockedUntil', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(
        buildMockUser({ failedLoginAttempts: 3 }),
      );

      await service.loginWithEmailPassword({ email: 'user@test.local', password: 'password123' });

      expect(mockPrismaService.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { failedLoginAttempts: 0, lockedUntil: null },
      });
    });
  });
});
KELASXTRA_PHASE5_AUTH_OWNERSHIP_22AUG2026

echo ""
echo ">> Semua file berhasil ditulis. Tidak ada perubahan schema/kode produksi -- murni test baru."
echo "Langkah selanjutnya:"
echo "1. npm run test        # unit test, termasuk auth.service.spec.ts yang baru"
echo "2. npm run test:e2e    # e2e test, termasuk 3 file baru: auth, content-ownership, question-banks"
