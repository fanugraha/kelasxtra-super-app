import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  createTestApp,
  registerStudent,
  registerTeacher,
  createAssessmentFixture,
  AssessmentFixture,
} from './utils/test-app.helper';

/**
 * AssessmentsService berbagi EvidenceService yang IDENTIK dengan
 * DiagnosticsService (lihat komentar di assessments.service.ts: "Jangan
 * membuat algoritma mastery berbeda antara Diagnostic dan Assessment").
 * Artinya Bug #1 dan Bug #2 dari QA audit 16 Agustus 2026 berlaku sama
 * persis di sini -- suite ini membuktikan fix-nya juga berlaku di jalur
 * Assessment, bukan cuma Diagnostic.
 *
 * Ini BUKAN pengganti full e2e suite (happy path/rollback/performance)
 * seperti punya Diagnostic -- itu masih item terpisah di roadmap
 * ("Salin pattern e2e test dari Diagnostic ke Assessment", rekomendasi
 * #5 di audit). Fokus suite ini murni security regression.
 */
describe('Assessments submission security (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fixture: AssessmentFixture;

  beforeAll(async () => {
    const ctx = await createTestApp();
    app = ctx.app;
    prisma = ctx.prisma;
    fixture = await createAssessmentFixture(prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  function buildAllCorrectAnswers() {
    return fixture.questions.map((q) => ({
      questionId: q.questionId,
      selectedOptionId: q.correctOptionId,
      timeSpentSeconds: 20,
    }));
  }

  describe('security: Bug #1 -- cross-question answer key exploit', () => {
    it('optionId benar milik soal lain dipakai ulang untuk semua soal -> TIDAK dianggap semuanya benar', async () => {
      const student = await registerStudent(app, 'asmt-exploit-cross-question');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const knownCorrectOptionId = fixture.questions[0].correctOptionId;
      const exploitAnswers = fixture.questions.map((q) => ({
        questionId: q.questionId,
        selectedOptionId: knownCorrectOptionId,
        timeSpentSeconds: 5,
      }));

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: exploitAnswers })
        .expect(201);

      // Assessment score dihitung berbobot points (bukan persen jawaban
      // benar biasa) -- cuma soal pertama yang benar-benar benar, jadi
      // skornya harus 1/6 dari total points, BUKAN 100%.
      const totalPoints = fixture.questions.reduce(
        (sum, q) => sum + q.points,
        0,
      );
      const expectedScore = (fixture.questions[0].points / totalPoints) * 100;
      expect(submitRes.body.data.overallScore).toBe(expectedScore);
      expect(submitRes.body.data.overallScore).not.toBe(100);

      const answers = await prisma.assessmentAnswer.findMany({
        where: { attemptId },
      });
      const correctAnswers = answers.filter((a) => a.isCorrect);
      expect(correctAnswers).toHaveLength(1);
      expect(correctAnswers[0].questionId).toBe(
        fixture.questions[0].questionId,
      );
    });
  });

  describe('security: Bug #2 -- duplicate questionId dalam satu submission', () => {
    it('questionId yang sama dikirim berulang kali dalam satu payload -> ditolak 400, tidak ada evidence yang tergelembung', async () => {
      const student = await registerStudent(
        app,
        'asmt-exploit-duplicate-question',
      );

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const easyQuestion = fixture.questions.find(
        (q) => q.difficulty === 'EASY',
      )!;
      const duplicateAnswers = Array.from({ length: 10 }, () => ({
        questionId: easyQuestion.questionId,
        selectedOptionId: easyQuestion.correctOptionId,
        timeSpentSeconds: 5,
      }));

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: duplicateAnswers })
        .expect(400);

      const answerCount = await prisma.assessmentAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(0);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });

  describe('security: RBAC -- role TEACHER tidak boleh akses endpoint assessments milik STUDENT', () => {
    it('TEACHER coba start attempt -> 403', async () => {
      const teacher = await registerTeacher(app, 'asmt-rbac-teacher-start');

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(403);
    });

    it('TEACHER coba submit -> 403 (bahkan dengan attemptId milik student lain)', async () => {
      const student = await registerStudent(app, 'asmt-rbac-victim');
      const teacher = await registerTeacher(app, 'asmt-rbac-teacher-submit');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(403);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: assessment
  // BOLEH diulang (beda dari diagnostic) -- yang dibatasi cuma jedanya
  // (cooldown), bukan jumlahnya. Lihat komentar
  // AssessmentsService.ATTEMPT_COOLDOWN_HOURS.
  // ============================================================

  describe('business rule: assessment boleh diulang tapi dengan cooldown', () => {
    it('attempt kedua sebelum cooldown selesai -> 409, setelah cooldown lewat -> boleh lagi', async () => {
      const student = await registerStudent(app, 'cooldown-test');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const firstAttemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId: firstAttemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      // Langsung coba lagi -- masih dalam cooldown 24 jam -> 409.
      const blockedRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(409);
      expect(blockedRes.body.message).toContain('jam');

      // Mundurkan completedAt attempt pertama 25 jam -- simulasikan cooldown
      // 24 jam sudah lewat, tanpa perlu benar-benar menunggu di dalam test.
      const twentyFiveHoursAgo = new Date(Date.now() - 25 * 3_600_000);
      await prisma.assessmentAttempt.update({
        where: { id: firstAttemptId },
        data: { completedAt: twentyFiveHoursAgo },
      });

      const secondStartRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStartRes.body.data.id).not.toBe(firstAttemptId);
      expect(secondStartRes.body.data.attemptNumber).toBe(2);
    });

    it('attempt IN_PROGRESS yang belum disubmit -> start lagi mengembalikan attempt yang sama, bukan bikin duplikat', async () => {
      const student = await registerStudent(app, 'asmt-resume-test');

      const firstStart = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      const secondStart = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStart.body.data.id).toBe(firstStart.body.data.id);
    });
  });

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: durationMinutes
  // ditegakkan sebagai SOFT FLAG (isFlagged), bukan blokir keras -- sama
  // persis polanya dengan diagnostic (lihat diagnostics.e2e-spec.ts).
  // ============================================================

  describe('business rule: durationMinutes ditegakkan sebagai soft flag, bukan blokir', () => {
    it('submit melebihi durationMinutes -> tetap diterima (201) tapi attempt ditandai isFlagged', async () => {
      // Assessment khusus dengan durationMinutes ketat, pakai teacherId &
      // soal yang sama dari fixture (tidak perlu bikin teacher/bank baru).
      const baseAssessment = await prisma.assessment.findUniqueOrThrow({
        where: { id: fixture.assessmentId },
      });
      const timedAssessment = await prisma.assessment.create({
        data: {
          subjectId: fixture.subjectId,
          teacherId: baseAssessment.teacherId,
          title: 'E2E Timed Assessment',
          type: 'FORMATIVE',
          durationMinutes: 1,
        },
      });
      for (const [index, q] of fixture.questions.entries()) {
        await prisma.assessmentQuestion.create({
          data: {
            assessmentId: timedAssessment.id,
            questionId: q.questionId,
            sequence: index,
            points: q.points,
          },
        });
      }

      const student = await registerStudent(app, 'asmt-duration-flag');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${timedAssessment.id}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const tenMinutesAgo = new Date(Date.now() - 10 * 60_000);
      await prisma.assessmentAttempt.update({
        where: { id: attemptId },
        data: { startedAt: tenMinutesAgo },
      });

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${timedAssessment.id}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201); // TETAP diterima -- soft flag, bukan blokir keras.

      expect(submitRes.body.data.overallScore).toBe(100);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.isFlagged).toBe(true);
      expect(attempt!.flagReason).toContain('Melebihi batas waktu');
    });
  });

  // ============================================================
  // Regression test untuk temuan QA audit #6: sama seperti diagnostic,
  // ini membuktikan idempotency guard tetap atomic walau dua request
  // submit dikirim bersamaan persis (Promise.all), bukan berurutan.
  // ============================================================

  describe('concurrency: dua request submit bersamaan persis (Promise.all)', () => {
    it('tepat satu yang sukses (201), satu lagi ditolak (409) -- bukan dua-duanya sukses / dua-duanya gagal', async () => {
      const student = await registerStudent(app, 'asmt-race-condition');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const answers = buildAllCorrectAnswers();

      const [resA, resB] = await Promise.all([
        request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
        request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
      ]);

      const statuses = [resA.status, resB.status].sort((a, b) => a - b);
      expect(statuses).toEqual([201, 409]);

      const answerCount = await prisma.assessmentAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(fixture.questions.length);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('SUBMITTED');
    });
  });

  // ============================================================
  // Regression test untuk temuan QA audit #9: endpoint GET
  // /assessments/:id/results yang disebut di dokumen master (section
  // 12.6) tapi belum pernah diimplementasikan sebelum ini -- hasil cuma
  // pernah ada di response submit() sekali itu saja.
  // ============================================================

  describe('GET /assessments/:id/results', () => {
    it('setelah submit -> bisa lihat hasilnya lagi lewat GET (bukan cuma sekali di response submit)', async () => {
      const student = await registerStudent(app, 'results-endpoint');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      const resultsRes = await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(200);

      expect(resultsRes.body.data.attempt.id).toBe(attemptId);
      expect(resultsRes.body.data.attempt.status).toBe('SUBMITTED');
      expect(resultsRes.body.data.answers).toHaveLength(fixture.questions.length);
      expect(resultsRes.body.data.competencySnapshots.length).toBeGreaterThan(0);
    });

    it('belum pernah submit -> 404, bukan array kosong yang membingungkan', async () => {
      const student = await registerStudent(app, 'results-none-yet');

      await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(404);
    });

    it('security: student lain tidak bisa lihat hasil attempt milik student ini lewat ?attemptId', async () => {
      const owner = await registerStudent(app, 'results-owner');
      const intruder = await registerStudent(app, 'results-intruder');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${owner.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${owner.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results?attemptId=${attemptId}`)
        .set('Authorization', `Bearer ${intruder.accessToken}`)
        .expect(403);
    });

    it('TEACHER tidak boleh akses endpoint ini sama sekali (403, RBAC STUDENT-only)', async () => {
      const teacher = await registerTeacher(app, 'results-rbac-teacher');

      await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(403);
    });
  });
});
