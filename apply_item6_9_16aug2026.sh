#!/bin/bash
set -e
echo ">> Menulis fix item #6 (true concurrent race test) dan #9 (GET /assessments/:id/results)..."

mkdir -p "$(dirname "src/assessments/assessments.service.ts")"
echo ">> Menulis src/assessments/assessments.service.ts"
cat > src/assessments/assessments.service.ts << 'KELASXTRA_APPLY_EOF_16AUG_ITEM6_9'
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EvidenceService } from '../learning-engine/evidence/evidence.service';
import { MasteryService } from '../learning-engine/mastery/mastery.service';
import type { UpdateCompetencyResult } from '../learning-engine/mastery/mastery.service';
import { CompetencySnapshotService } from '../learning-engine/snapshots/competency-snapshot.service';
import { LearningEngineConfigService } from '../learning-engine/config/learning-engine-config.service';
import { LearningPathReconciler } from '../learning-engine/learning-path/learning-path-reconciler';
import { SubmitAssessmentDto } from './dto/submit-assessment.dto';
import { detectSuspiciousTiming } from '../learning-engine/integrity/suspicious-timing-detector';

@Injectable()
export class AssessmentsService {
  constructor(
    private prisma: PrismaService,
    private evidenceService: EvidenceService,
    private masteryService: MasteryService,
    private competencySnapshotService: CompetencySnapshotService,
    private learningEngineConfigService: LearningEngineConfigService,
    private learningPathReconciler: LearningPathReconciler,
  ) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({
      where: { userId },
    });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  // Keputusan bisnis (16 Agustus 2026): assessment BOLEH diulang -- beda
  // peran dari diagnostic (lihat DiagnosticsService.startAttempt). Ini
  // memang cara sistem "belajar" tentang perkembangan siswa dari waktu ke
  // waktu (confidence naik pelan-pelan lewat EMA seiring makin banyak
  // evidence masuk). Yang dibatasi bukan JUMLAH ulangnya, tapi JEDANYA --
  // supaya siswa tidak spam submit berkali-kali dalam semenit cuma buat
  // menggelembungkan confidence score secara artifisial, bukan belajar beneran.
  private static readonly ATTEMPT_COOLDOWN_HOURS = 24;

  async startAttempt(userId: number, assessmentId: number) {
    const profile = await this.findProfileByUserId(userId);

    const assessment = await this.prisma.assessment.findUnique({
      where: { id: assessmentId },
    });

    if (!assessment) {
      throw new NotFoundException('Assessment tidak ditemukan.');
    }

    const latestAttempt = await this.prisma.assessmentAttempt.findFirst({
      where: { assessmentId, studentId: profile.id },
      orderBy: { startedAt: 'desc' },
    });

    // Attempt lama masih IN_PROGRESS -- lanjutkan yang sama, jangan bikin duplikat.
    if (latestAttempt?.status === 'IN_PROGRESS') {
      return latestAttempt;
    }

    if (latestAttempt?.status === 'SUBMITTED' && latestAttempt.completedAt) {
      const hoursSinceLastAttempt =
        (Date.now() - latestAttempt.completedAt.getTime()) / 3_600_000;

      if (hoursSinceLastAttempt < AssessmentsService.ATTEMPT_COOLDOWN_HOURS) {
        const hoursRemaining = Math.ceil(
          AssessmentsService.ATTEMPT_COOLDOWN_HOURS - hoursSinceLastAttempt,
        );
        throw new ConflictException(
          `Kamu baru saja mengerjakan assessment ini. Coba lagi dalam ${hoursRemaining} jam.`,
        );
      }
    }

    const previousAttemptsCount = await this.prisma.assessmentAttempt.count({
      where: { assessmentId, studentId: profile.id },
    });

    return this.prisma.assessmentAttempt.create({
      data: {
        assessmentId,
        studentId: profile.id,
        attemptNumber: previousAttemptsCount + 1,
        status: 'IN_PROGRESS',
      },
    });
  }

  /**
   * Sama persis alurnya dengan DiagnosticsService.submit() -- keduanya
   * memakai Learning Engine yang sama (spec Phase 4 bagian 13: "Jangan
   * membuat algoritma mastery berbeda antara Diagnostic dan Assessment").
   *
   * SATU perbedaan struktural: skor attempt di sini dihitung berbobot
   * `points` per soal (field yang memang cuma ada di AssessmentQuestion,
   * tidak ada di DiagnosticQuestion) -- bukan sekadar persen jawaban
   * benar seperti di diagnostic. Ini tetap "Assessment Score", BUKAN
   * "Mastery Score" (section 21) -- masteryScore tetap dihitung EMA lewat
   * MasteryService yang identik dengan diagnostic.
   */
  async submit(userId: number, assessmentId: number, dto: SubmitAssessmentDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.$transaction(async (tx) => {
      // 2. Validate attempt ownership
      const attempt = await tx.assessmentAttempt.findUnique({
        where: { id: dto.attemptId },
      });

      if (!attempt) {
        throw new NotFoundException('Attempt tidak ditemukan.');
      }
      if (attempt.studentId !== profile.id) {
        throw new ForbiddenException('Attempt ini bukan milik kamu.');
      }
      if (attempt.assessmentId !== assessmentId) {
        throw new BadRequestException(
          'Attempt ini bukan untuk assessment ini.',
        );
      }

      // 3. Validate attempt status -- idempotency guard ATOMIC, sama
      // persis polanya dengan DiagnosticsService.
      const guarded = await tx.assessmentAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException(
          'Attempt ini sudah pernah disubmit sebelumnya.',
        );
      }

      // 4. Validate submitted answers + sekaligus ambil `points` per soal
      // dalam SATU query (bukan dua query terpisah untuk validasi dan
      // untuk ambil points). Juga tolak questionId yang dikirim berulang
      // dalam satu payload (fix Bug #2 QA audit 16 Agustus 2026 -- pola
      // sama persis dengan DiagnosticsService).
      const assessmentQuestions = await tx.assessmentQuestion.findMany({
        where: { assessmentId },
        select: { questionId: true, points: true },
      });
      const pointsByQuestionId = new Map(
        assessmentQuestions.map((q) => [q.questionId, Number(q.points)]),
      );
      const seenQuestionIds = new Set<number>();

      for (const answer of dto.answers) {
        if (!pointsByQuestionId.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari assessment ini.`,
          );
        }
        if (seenQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} dikirim lebih dari sekali dalam satu submission.`,
          );
        }
        seenQuestionIds.add(answer.questionId);
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness -- SAMA PERSIS dengan diagnostic,
      // service yang dipakai pun sama (EvidenceService).
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } =
        await this.evidenceService.loadAndAggregate(tx, normalizedAnswers);

      // 8. Insert AssessmentAnswer (bulk), sekalian hitung pointsEarned
      // per jawaban dari map yang sudah di-load di step 4.
      await tx.assessmentAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          pointsEarned: a.isCorrect
            ? (pointsByQuestionId.get(a.questionId) ?? 0)
            : 0,
          timeSpentSeconds: a.timeSpentSeconds ?? undefined,
        })),
      });

      // 9-14. Per competency yang tersentuh: EMA mastery, confidence,
      // classify bucket, snapshot, reconcile learning path -- LEARNING
      // ENGINE YANG SAMA dengan diagnostic, cuma sourceType-nya beda.
      const config = await this.learningEngineConfigService.getActiveConfig(tx);
      const competencyResults: UpdateCompetencyResult[] = [];

      for (const [competencyId, evidence] of evidenceByCompetency) {
        const result = await this.masteryService.updateForCompetency(tx, {
          studentId: profile.id,
          competencyId,
          evidence,
          config,
        });

        await this.competencySnapshotService.create(tx, {
          studentId: profile.id,
          competencyId,
          masteryScore: result.newMasteryScore,
          confidenceScore: result.newConfidenceScore,
          totalAnswered: result.totalAnswered,
          totalCorrect: result.totalCorrect,
          masteryBucket: result.newBucket,
          triggeredByAttemptId: attempt.id,
          sourceType: 'ASSESSMENT',
          engineVersion: config.engineVersion,
          configVersion: config.configVersion,
        });

        if (result.bucketChanged) {
          await this.learningPathReconciler.reconcile(tx, {
            studentId: profile.id,
            competencyId,
            oldBucket: result.oldBucket,
            newBucket: result.newBucket,
          });
        }

        competencyResults.push(result);
      }

      // 15. Update AssessmentAttempt -- score berbobot points (BUKAN
      // masteryScore), & completedAt.
      let totalPossiblePoints = 0;
      let totalEarnedPoints = 0;

      for (const a of enrichedAnswers) {
        const possible = pointsByQuestionId.get(a.questionId) ?? 0;
        totalPossiblePoints += possible;
        if (a.isCorrect) {
          totalEarnedPoints += possible;
        }
      }

      const overallScore =
        totalPossiblePoints > 0
          ? (totalEarnedPoints / totalPossiblePoints) * 100
          : 0;

      // Sesi 6: deteksi timing mencurigakan -- pola identik dengan
      // DiagnosticsService, fungsi pure yang sama-sama di-reuse.
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      // Keputusan bisnis (16 Agustus 2026, item #3): sama seperti diagnostic
      // -- durationMinutes jadi SOFT FLAG, bukan blokir keras. Assessment di
      // Kelasxtra berperan sebagai latihan/check-in berkala (bukan ujian
      // formal sekali-jalan), jadi menolak submit yang telat bertentangan
      // dengan tujuan mendorong siswa terus berlatih.
      const assessment = await tx.assessment.findUnique({
        where: { id: assessmentId },
        select: { durationMinutes: true },
      });
      const elapsedMinutes =
        (Date.now() - attempt.startedAt.getTime()) / 60_000;
      const isOverDuration =
        assessment?.durationMinutes != null &&
        elapsedMinutes > assessment.durationMinutes;

      const flagReasons = [
        ...(timingCheck.isFlagged && timingCheck.flagReason ? [timingCheck.flagReason] : []),
        ...(isOverDuration
          ? [
              `Melebihi batas waktu pengerjaan (${assessment!.durationMinutes} menit, selesai dalam ${Math.round(elapsedMinutes)} menit).`,
            ]
          : []),
      ];
      const isFlagged = timingCheck.isFlagged || isOverDuration;

      const updatedAttempt = await tx.assessmentAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(isFlagged
            ? {
                isFlagged: true,
                flagReason: flagReasons.join(' | '),
                flaggedAt: new Date(),
              }
            : {}),
        },
      });

      // 17. Return learning profile.
      return {
        attempt: updatedAttempt,
        overallScore,
        competencyResults,
      };
    });
  }

  // Fix #9 (QA audit 16 Agustus 2026): sebelumnya hasil assessment CUMA
  // ada di response submit() sekali itu saja -- kalau siswa nutup
  // halamannya atau mau lihat lagi besok, tidak ada cara sama sekali.
  // Endpoint ini disebut eksplisit di dokumen master (section 12.6) tapi
  // belum pernah diimplementasikan.
  //
  // Tanpa query attemptId -> ambil attempt SUBMITTED paling baru untuk
  // assessment ini (hasil "current" yang paling relevan buat siswa).
  // Dengan attemptId -> lihat attempt spesifik (riwayat, karena sekarang
  // assessment boleh diulang -- lihat startAttempt).
  async getResults(userId: number, assessmentId: number, attemptId?: number) {
    const profile = await this.findProfileByUserId(userId);

    const attempt = attemptId
      ? await this.prisma.assessmentAttempt.findUnique({ where: { id: attemptId } })
      : await this.prisma.assessmentAttempt.findFirst({
          where: { assessmentId, studentId: profile.id, status: 'SUBMITTED' },
          orderBy: { completedAt: 'desc' },
        });

    if (!attempt) {
      throw new NotFoundException(
        attemptId
          ? 'Attempt tidak ditemukan.'
          : 'Belum ada attempt yang disubmit untuk assessment ini.',
      );
    }
    if (attempt.studentId !== profile.id) {
      throw new ForbiddenException('Attempt ini bukan milik kamu.');
    }
    if (attempt.assessmentId !== assessmentId) {
      throw new BadRequestException('Attempt ini bukan untuk assessment ini.');
    }
    if (attempt.status !== 'SUBMITTED') {
      throw new BadRequestException('Attempt ini belum disubmit, belum ada hasil.');
    }

    const answers = await this.prisma.assessmentAnswer.findMany({
      where: { attemptId: attempt.id },
      include: {
        question: { select: { id: true, questionText: true, difficulty: true, competencyId: true } },
      },
    });

    // Snapshot mastery yang di-trigger OLEH attempt spesifik ini --
    // append-only, jadi ini rekonstruksi akurat dari competencyResults
    // yang dulu cuma sempat dikembalikan sekali di response submit().
    const competencySnapshots = await this.prisma.competencySnapshot.findMany({
      where: { triggeredByAttemptId: attempt.id, sourceType: 'ASSESSMENT' },
    });

    return { attempt, answers, competencySnapshots };
  }
KELASXTRA_APPLY_EOF_16AUG_ITEM6_9

mkdir -p "$(dirname "src/assessments/assessments.controller.ts")"
echo ">> Menulis src/assessments/assessments.controller.ts"
cat > src/assessments/assessments.controller.ts << 'KELASXTRA_APPLY_EOF_16AUG_ITEM6_9'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AssessmentsService } from './assessments.service';
import { SubmitAssessmentDto } from './dto/submit-assessment.dto';

@Controller('assessments')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class AssessmentsController {
  constructor(private assessmentsService: AssessmentsService) {}

  @Post(':id/start')
  async start(@CurrentUser() user: { userId: number }, @Param('id', ParseIntPipe) id: number) {
    const attempt = await this.assessmentsService.startAttempt(user.userId, id);
    return { success: true, data: attempt, message: 'Attempt dimulai' };
  }

  @Post(':id/submit')
  async submit(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: SubmitAssessmentDto,
  ) {
    const result = await this.assessmentsService.submit(user.userId, id, dto);
    return { success: true, data: result, message: 'Assessment berhasil disubmit' };
  }

  // Fix #9: sesuai dokumen master section 12.6, tapi belum pernah ada
  // implementasinya sebelum ini. Tanpa ?attemptId -> hasil attempt
  // SUBMITTED paling baru. Dengan ?attemptId -> lihat attempt spesifik
  // (assessment boleh diulang, jadi bisa ada beberapa hasil di riwayat).
  @Get(':id/results')
  async results(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Query('attemptId') attemptIdRaw?: string,
  ) {
    const attemptId = attemptIdRaw ? Number(attemptIdRaw) : undefined;
    const result = await this.assessmentsService.getResults(user.userId, id, attemptId);
    return { success: true, data: result, message: 'Hasil assessment' };
  }
}
KELASXTRA_APPLY_EOF_16AUG_ITEM6_9

mkdir -p "$(dirname "test/diagnostics.e2e-spec.ts")"
echo ">> Menulis test/diagnostics.e2e-spec.ts"
cat > test/diagnostics.e2e-spec.ts << 'KELASXTRA_APPLY_EOF_16AUG_ITEM6_9'
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  createTestApp,
  registerStudent,
  registerTeacher,
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
          studentId_competencyId: {
            studentId: studentProfile!.id,
            competencyId,
          },
        },
      });

      expect(competencyState).not.toBeNull();
      expect(competencyState!.totalAnswered).toBe(3); // 3 soal per competency
      expect(competencyState!.totalCorrect).toBe(3);
      expect(Number(competencyState!.masteryScore)).toBe(100); // first-attempt rule

      // Fix temuan QA audit #5 (16 Agustus 2026): test lama tidak pernah
      // assert masteryBucket. Dengan config default (confidenceK=5,
      // minimumConfidence=0.60), 3 jawaban -> confidence = 1-e^(-3/5) ≈
      // 0.451, DI BAWAH ambang 0.60. Jadi walau masteryScore=100, bucket
      // HARUS INSUFFICIENT_DATA, bukan MASTERED -- confidence gate
      // dievaluasi duluan sebelum threshold mastery (lihat mastery-classifier.ts).
      expect(competencyState!.masteryBucket).toBe('INSUFFICIENT_DATA');

      const snapshots = await prisma.competencySnapshot.findMany({
        where: { studentId: studentProfile!.id, competencyId },
      });
      expect(snapshots).toHaveLength(1);
      expect(snapshots[0].sourceType).toBe('DIAGNOSTIC');
      expect(snapshots[0].triggeredByAttemptId).toBe(attemptId);
      expect(snapshots[0].masteryBucket).toBe('INSUFFICIENT_DATA');
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

    const answerCount = await prisma.diagnosticAnswer.count({
      where: { attemptId },
    });
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
    const attempt = await prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });
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
    const answerCount = await prisma.diagnosticAnswer.count({
      where: { attemptId },
    });
    expect(answerCount).toBe(0);

    const attempt = await prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });
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

  // ============================================================
  // Regression test untuk temuan QA audit 16 Agustus 2026.
  // ============================================================

  describe('security: Bug #1 -- cross-question answer key exploit', () => {
    it('optionId benar milik soal lain dipakai ulang untuk semua soal -> TIDAK dianggap semuanya benar', async () => {
      const student = await registerStudent(app, 'exploit-cross-question');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      // Exploit: pakai SATU optionId yang benar (milik soal pertama) untuk
      // SEMUA soal lain dalam payload. Sebelum fix, ini bikin semua jawaban
      // dianggap benar (overallScore 100%) walau cuma 1 optionId yang valid.
      const knownCorrectOptionId = fixture.questions[0].correctOptionId;
      const exploitAnswers = fixture.questions.map((q) => ({
        questionId: q.questionId,
        selectedOptionId: knownCorrectOptionId,
        timeSpentSeconds: 5,
      }));

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: exploitAnswers })
        .expect(201);

      // Cuma soal pertama (pemilik asli optionId itu) yang benar-benar
      // benar. Sisanya harus dianggap salah, BUKAN ikut 100%.
      const expectedCorrectCount = 1;
      const expectedScore =
        (expectedCorrectCount / fixture.questions.length) * 100;
      expect(submitRes.body.data.overallScore).toBe(expectedScore);
      expect(submitRes.body.data.overallScore).not.toBe(100);

      const answers = await prisma.diagnosticAnswer.findMany({
        where: { attemptId },
      });
      const correctAnswers = answers.filter((a) => a.isCorrect);
      expect(correctAnswers).toHaveLength(expectedCorrectCount);
      expect(correctAnswers[0].questionId).toBe(
        fixture.questions[0].questionId,
      );
    });
  });

  describe('security: Bug #2 -- duplicate questionId dalam satu submission', () => {
    it('questionId yang sama dikirim berulang kali dalam satu payload -> ditolak 400, tidak ada evidence yang tergelembung', async () => {
      const student = await registerStudent(app, 'exploit-duplicate-question');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      // Exploit: satu soal mudah yang jawabannya diketahui, dikirim
      // berulang kali untuk menggelembungkan totalAnswered/confidence.
      const easyQuestion = fixture.questions.find(
        (q) => q.difficulty === 'EASY',
      )!;
      const duplicateAnswers = Array.from({ length: 10 }, () => ({
        questionId: easyQuestion.questionId,
        selectedOptionId: easyQuestion.correctOptionId,
        timeSpentSeconds: 5,
      }));

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: duplicateAnswers })
        .expect(400);

      // Karena ditolak validasi di dalam transaction, TIDAK BOLEH ada
      // answer yang ke-insert dan attempt harus tetap IN_PROGRESS -- sama
      // seperti test rollback untuk question tidak valid di atas.
      const answerCount = await prisma.diagnosticAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(0);

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });

  describe('security: RBAC -- role TEACHER tidak boleh akses endpoint diagnostics milik STUDENT', () => {
    it('TEACHER coba start attempt -> 403', async () => {
      const teacher = await registerTeacher(app, 'rbac-teacher-start');

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(403);
    });

    it('TEACHER coba submit -> 403 (bahkan dengan attemptId milik student lain)', async () => {
      const student = await registerStudent(app, 'rbac-victim');
      const teacher = await registerTeacher(app, 'rbac-teacher-submit');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(403);

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: diagnostic
  // dibatasi 1x per siswa per test (bukan latihan yang boleh diulang
  // bebas -- lihat komentar DiagnosticsService.startAttempt), dengan
  // jalur reset lewat ADMIN/TEACHER "void" attempt lama.
  // ============================================================

  describe('business rule: diagnostic dibatasi 1x, ADMIN/TEACHER bisa void untuk reset', () => {
    it('attempt kedua ke diagnostic test yang sama -> 409, lalu void oleh TEACHER -> siswa bisa attempt lagi', async () => {
      const student = await registerStudent(app, 'cap-test');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const firstAttemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId: firstAttemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      // Attempt sudah SUBMITTED -- attempt kedua harus ditolak.
      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(409);

      // STUDENT sendiri tidak boleh void attempt-nya sendiri (RBAC).
      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/attempts/${firstAttemptId}/void`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ reason: 'coba reset sendiri' })
        .expect(403);

      // TEACHER void attempt lama -- jalur reset yang benar.
      const teacher = await registerTeacher(app, 'cap-test-teacher');
      const voidRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/attempts/${firstAttemptId}/void`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ reason: 'kendala teknis saat tes pertama' })
        .expect(201);

      expect(voidRes.body.data.status).toBe('VOID');
      expect(voidRes.body.data.voidedByUserId).toBe(teacher.userId);

      // Void attempt yang sama dua kali -> 409, bukan diam-diam sukses lagi.
      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/attempts/${firstAttemptId}/void`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ reason: 'coba void lagi' })
        .expect(409);

      // Sekarang attempt baru boleh dimulai lagi.
      const secondStartRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStartRes.body.data.id).not.toBe(firstAttemptId);
      expect(secondStartRes.body.data.attemptNumber).toBe(2);
    });

    it('attempt IN_PROGRESS yang belum disubmit -> start lagi mengembalikan attempt yang sama, bukan bikin duplikat', async () => {
      const student = await registerStudent(app, 'resume-test');

      const firstStart = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      const secondStart = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStart.body.data.id).toBe(firstStart.body.data.id);
    });
  });

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: durationMinutes
  // ditegakkan sebagai SOFT FLAG (isFlagged), bukan blokir keras -- attempt
  // yang telat tetap diterima & tetap dihitung skornya.
  // ============================================================

  describe('business rule: durationMinutes ditegakkan sebagai soft flag, bukan blokir', () => {
    it('submit melebihi durationMinutes -> tetap diterima (201) tapi attempt ditandai isFlagged', async () => {
      // Diagnostic test khusus dengan durationMinutes ketat, pakai soal
      // yang sama dari fixture (tidak perlu bikin question bank baru).
      const timedTest = await prisma.diagnosticTest.create({
        data: {
          subjectId: fixture.subjectId,
          name: 'E2E Timed Diagnostic',
          durationMinutes: 1,
        },
      });
      for (const [index, q] of fixture.questions.entries()) {
        await prisma.diagnosticQuestion.create({
          data: {
            diagnosticTestId: timedTest.id,
            questionId: q.questionId,
            sequence: index,
          },
        });
      }

      const student = await registerStudent(app, 'duration-flag');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${timedTest.id}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      // Backdate startedAt -- simulasikan siswa sudah mengerjakan 10 menit,
      // padahal batas waktunya cuma 1 menit. Lebih cepat & lebih stabil
      // daripada benar-benar menunggu di dalam test.
      const tenMinutesAgo = new Date(Date.now() - 10 * 60_000);
      await prisma.diagnosticAttempt.update({
        where: { id: attemptId },
        data: { startedAt: tenMinutesAgo },
      });

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${timedTest.id}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201); // TETAP diterima -- soft flag, bukan blokir keras.

      expect(submitRes.body.data.overallScore).toBe(100); // skor tetap dihitung normal

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.isFlagged).toBe(true);
      expect(attempt!.flagReason).toContain('Melebihi batas waktu');
    });
  });

  // ============================================================
  // Regression test untuk temuan QA audit #6: test duplicate submission
  // yang sudah ada sebelumnya (di atas) submit BERURUTAN (await satu-satu),
  // itu belum benar-benar membuktikan idempotency guard atomic di level
  // database. Test ini mengirim dua request submit BERSAMAAN PERSIS lewat
  // Promise.all -- baru ini bukti yang sebenarnya.
  // ============================================================

  describe('concurrency: dua request submit bersamaan persis (Promise.all)', () => {
    it('tepat satu yang sukses (201), satu lagi ditolak (409) -- bukan dua-duanya sukses / dua-duanya gagal', async () => {
      const student = await registerStudent(app, 'race-condition');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const answers = buildAllCorrectAnswers();

      // Promise.all, BUKAN await satu-satu -- dua request submit
      // dikirim di waktu yang nyaris bersamaan persis, membuktikan
      // idempotency guard (updateMany WHERE status=IN_PROGRESS) memang
      // atomic di level database, bukan cuma aman kalau dites berurutan.
      const [resA, resB] = await Promise.all([
        request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
        request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
      ]);

      const statuses = [resA.status, resB.status].sort((a, b) => a - b);
      expect(statuses).toEqual([201, 409]);

      // Jawaban tidak boleh kedobel walau dua request diproses bersamaan.
      const answerCount = await prisma.diagnosticAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(fixture.questions.length);

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('SUBMITTED');
    });
  });
});
KELASXTRA_APPLY_EOF_16AUG_ITEM6_9

mkdir -p "$(dirname "test/assessments.e2e-spec.ts")"
echo ">> Menulis test/assessments.e2e-spec.ts"
cat > test/assessments.e2e-spec.ts << 'KELASXTRA_APPLY_EOF_16AUG_ITEM6_9'
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
KELASXTRA_APPLY_EOF_16AUG_ITEM6_9

echo ""
echo ">> Semua file berhasil ditulis."
echo ""
echo "Tidak ada perubahan schema -- tidak perlu migration/prisma generate."
echo "Langkah selanjutnya:"
echo "1. npm run test:e2e"
echo ""
echo "Test baru yang WAJIB PASS:"
echo "  - diagnostics.e2e-spec.ts > concurrency: dua request submit bersamaan persis"
echo "  - assessments.e2e-spec.ts > concurrency: dua request submit bersamaan persis"
echo "  - assessments.e2e-spec.ts > GET /assessments/:id/results (4 test: happy path, 404, security, RBAC)"
