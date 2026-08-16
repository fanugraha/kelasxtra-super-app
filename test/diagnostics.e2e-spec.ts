import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  createTestApp,
  registerStudent,
  createDiagnosticFixture,
  DiagnosticFixture,
} from './utils/test-app.helper';

describe('Diagnostics submission (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fixture: DiagnosticFixture;

  beforeAll(async () => {
    const ctx = await createTestApp();
    app = ctx.app;
    prisma = ctx.prisma;
    fixture = await createDiagnosticFixture(prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  // Semua jawaban benar -> attemptAccuracy 100% -> first-attempt rule
  // (spec bagian 5.1): masteryScore = attemptAccuracy, bukan EMA.
  function buildAllCorrectAnswers() {
    return fixture.questions.map((q) => ({
      questionId: q.questionId,
      selectedOptionId: q.correctOptionId,
      timeSpentSeconds: 20,
    }));
  }

  it('happy path: submit diagnostic membuat StudentCompetency + CompetencySnapshot untuk tiap competency yang tersentuh', async () => {
    const student = await registerStudent(app, 'happy-path');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);

    const attemptId = startRes.body.data.id;

    const submitRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers: buildAllCorrectAnswers() })
      .expect(201);

    expect(submitRes.body.success).toBe(true);
    expect(submitRes.body.data.overallScore).toBe(100);
    expect(submitRes.body.data.competencyResults).toHaveLength(2);

    const studentProfile = await prisma.studentProfile.findUnique({
      where: { userId: student.userId },
    });

    for (const competencyId of fixture.competencyIds) {
      const competencyState = await prisma.studentCompetency.findUnique({
        where: {
          studentId_competencyId: { studentId: studentProfile!.id, competencyId },
        },
      });

      expect(competencyState).not.toBeNull();
      expect(competencyState!.totalAnswered).toBe(3); // 3 soal per competency
      expect(competencyState!.totalCorrect).toBe(3);
      expect(Number(competencyState!.masteryScore)).toBe(100); // first-attempt rule

      const snapshots = await prisma.competencySnapshot.findMany({
        where: { studentId: studentProfile!.id, competencyId },
      });
      expect(snapshots).toHaveLength(1);
      expect(snapshots[0].sourceType).toBe('DIAGNOSTIC');
      expect(snapshots[0].triggeredByAttemptId).toBe(attemptId);
    }
  });

  it('duplicate submission: submit attempt yang sama dua kali -> request kedua ditolak 409, counter tidak dobel', async () => {
    const student = await registerStudent(app, 'duplicate-sub');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    const answers = buildAllCorrectAnswers();

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers })
      .expect(201);

    // Submit kedua, attempt yang sama persis -> harus 409, bukan sukses lagi.
    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers })
      .expect(409);

    const studentProfile = await prisma.studentProfile.findUnique({
      where: { userId: student.userId },
    });

    const answerCount = await prisma.diagnosticAnswer.count({ where: { attemptId } });
    expect(answerCount).toBe(fixture.questions.length); // bukan 2x lipat

    const competencyState = await prisma.studentCompetency.findUnique({
      where: {
        studentId_competencyId: {
          studentId: studentProfile!.id,
          competencyId: fixture.competencyIds[0],
        },
      },
    });
    expect(competencyState!.totalAnswered).toBe(3); // bukan 6
  });

  it('security: student lain tidak bisa submit attempt milik student ini (403)', async () => {
    const owner = await registerStudent(app, 'owner');
    const intruder = await registerStudent(app, 'intruder');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${intruder.accessToken}`)
      .send({ attemptId, answers: buildAllCorrectAnswers() })
      .expect(403);

    // Attempt milik owner harus tetap IN_PROGRESS, belum tersentuh sama sekali.
    const attempt = await prisma.diagnosticAttempt.findUnique({ where: { id: attemptId } });
    expect(attempt!.status).toBe('IN_PROGRESS');
  });

  it('rollback: question tidak valid di tengah batch -> tidak ada partial write (answer/competency tidak berubah)', async () => {
    const student = await registerStudent(app, 'rollback');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    const answers = [
      ...buildAllCorrectAnswers(),
      { questionId: 999999, selectedOptionId: null, timeSpentSeconds: 10 }, // question invalid
    ];

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers })
      .expect(400);

    // Karena gagal di dalam transaction, TIDAK BOLEH ada answer yang
    // ke-insert sama sekali, dan attempt harus tetap IN_PROGRESS (guard
    // idempotency di step 3 juga ikut ter-rollback).
    const answerCount = await prisma.diagnosticAnswer.count({ where: { attemptId } });
    expect(answerCount).toBe(0);

    const attempt = await prisma.diagnosticAttempt.findUnique({ where: { id: attemptId } });
    expect(attempt!.status).toBe('IN_PROGRESS');
  });

  it('performance sanity: submit 6 jawaban lintas 2 competency selesai dalam waktu wajar (bukti tidak ada full-history recomputation)', async () => {
    const student = await registerStudent(app, 'perf-sanity');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    const startTime = Date.now();

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers: buildAllCorrectAnswers() })
      .expect(201);

    const elapsedMs = Date.now() - startTime;

    // Sanity check kasar, bukan micro-benchmark presisi: kalau submission
    // diam-diam melakukan full-history recomputation (mis. query semua
    // historical answer per competency), elapsed time akan melonjak jauh
    // di atas ini seiring data bertambah. 2 detik jauh di atas ekspektasi
    // normal (harusnya <200ms lokal) tapi cukup toleran untuk CI yang lambat.
    expect(elapsedMs).toBeLessThan(2000);
  });
});
