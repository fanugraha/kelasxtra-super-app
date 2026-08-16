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
import { SubmitDiagnosticDto } from './dto/submit-diagnostic.dto';

@Injectable()
export class DiagnosticsService {
  constructor(
    private prisma: PrismaService,
    private evidenceService: EvidenceService,
    private masteryService: MasteryService,
    private competencySnapshotService: CompetencySnapshotService,
    private learningEngineConfigService: LearningEngineConfigService,
    private learningPathReconciler: LearningPathReconciler,
  ) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({ where: { userId } });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  // Step 1 (start): buat attempt baru, status IN_PROGRESS.
  async startAttempt(userId: number, diagnosticTestId: number) {
    const profile = await this.findProfileByUserId(userId);

    const diagnosticTest = await this.prisma.diagnosticTest.findUnique({
      where: { id: diagnosticTestId },
    });

    if (!diagnosticTest) {
      throw new NotFoundException('Diagnostic test tidak ditemukan.');
    }

    const previousAttemptsCount = await this.prisma.diagnosticAttempt.count({
      where: { diagnosticTestId, studentId: profile.id },
    });

    return this.prisma.diagnosticAttempt.create({
      data: {
        diagnosticTestId,
        studentId: profile.id,
        attemptNumber: previousAttemptsCount + 1,
        status: 'IN_PROGRESS',
      },
    });
  }

  /**
   * Alur 17 langkah sesuai spec Phase 4 bagian 12, semuanya dalam SATU
   * database transaction (bagian 14: "harus diproses dalam satu database
   * transaction ... jangan sampai answer berhasil masuk tapi
   * StudentCompetency gagal update").
   */
  async submit(userId: number, diagnosticTestId: number, dto: SubmitDiagnosticDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.$transaction(async (tx) => {
      // 2. Validate attempt ownership
      const attempt = await tx.diagnosticAttempt.findUnique({
        where: { id: dto.attemptId },
      });

      if (!attempt) {
        throw new NotFoundException('Attempt tidak ditemukan.');
      }
      if (attempt.studentId !== profile.id) {
        throw new ForbiddenException('Attempt ini bukan milik kamu.');
      }
      if (attempt.diagnosticTestId !== diagnosticTestId) {
        throw new BadRequestException('Attempt ini bukan untuk diagnostic test ini.');
      }

      // 3. Validate attempt status -- idempotency guard yang ATOMIC.
      // UPDATE ... WHERE status='IN_PROGRESS' mengunci baris ini di dalam
      // transaction; kalau ada request submit kedua (double-klik/retry)
      // yang datang bersamaan, salah satunya pasti dapat count=0 di sini
      // dan gagal SEBELUM sempat memproses jawaban apa pun.
      const guarded = await tx.diagnosticAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException('Attempt ini sudah pernah disubmit sebelumnya.');
      }

      // 4. Validate submitted answers -- questionId harus benar-benar
      // bagian dari diagnostic test ini (bukan soal dari test lain).
      const validQuestions = await tx.diagnosticQuestion.findMany({
        where: { diagnosticTestId },
        select: { questionId: true },
      });
      const validQuestionIds = new Set(validQuestions.map((q) => q.questionId));

      for (const answer of dto.answers) {
        if (!validQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari diagnostic test ini.`,
          );
        }
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness.
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } = await this.evidenceService.loadAndAggregate(
        tx,
        normalizedAnswers,
      );

      // 8. Insert DiagnosticAnswer (bulk, bukan satu-satu).
      await tx.diagnosticAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          timeSpentSeconds: a.timeSpentSeconds ?? undefined,
        })),
      });

      // 9-14. Per competency yang tersentuh: EMA mastery, confidence,
      // classify bucket, snapshot, dan reconcile learning path HANYA kalau
      // bucket-nya berubah.
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
          sourceType: 'DIAGNOSTIC',
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

      // 15. Update DiagnosticAttempt -- score & completedAt (status sudah
      // SUBMITTED dari guard di step 3). Skor attempt ini SENGAJA dipisah
      // dari masteryScore (spec bagian 21: Assessment Score != Mastery
      // Score) -- ini murni persentase benar di attempt ini saja, tanpa
      // difficulty weighting maupun EMA.
      const correctCount = enrichedAnswers.filter((a) => a.isCorrect).length;
      const overallScore = (correctCount / enrichedAnswers.length) * 100;

      const updatedAttempt = await tx.diagnosticAttempt.update({
        where: { id: attempt.id },
        data: { score: overallScore, completedAt: new Date() },
      });

      // 17. Return learning profile.
      return {
        attempt: updatedAttempt,
        overallScore,
        competencyResults,
      };
    });
  }
}
