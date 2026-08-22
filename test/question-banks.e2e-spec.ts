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
