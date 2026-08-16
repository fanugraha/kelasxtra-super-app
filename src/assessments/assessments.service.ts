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
    const profile = await this.prisma.studentProfile.findUnique({ where: { userId } });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  async startAttempt(userId: number, assessmentId: number) {
    const profile = await this.findProfileByUserId(userId);

    const assessment = await this.prisma.assessment.findUnique({
      where: { id: assessmentId },
    });

    if (!assessment) {
      throw new NotFoundException('Assessment tidak ditemukan.');
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
        throw new BadRequestException('Attempt ini bukan untuk assessment ini.');
      }

      // 3. Validate attempt status -- idempotency guard ATOMIC, sama
      // persis polanya dengan DiagnosticsService.
      const guarded = await tx.assessmentAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException('Attempt ini sudah pernah disubmit sebelumnya.');
      }

      // 4. Validate submitted answers + sekaligus ambil `points` per soal
      // dalam SATU query (bukan dua query terpisah untuk validasi dan
      // untuk ambil points).
      const assessmentQuestions = await tx.assessmentQuestion.findMany({
        where: { assessmentId },
        select: { questionId: true, points: true },
      });
      const pointsByQuestionId = new Map(
        assessmentQuestions.map((q) => [q.questionId, Number(q.points)]),
      );

      for (const answer of dto.answers) {
        if (!pointsByQuestionId.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari assessment ini.`,
          );
        }
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness -- SAMA PERSIS dengan diagnostic,
      // service yang dipakai pun sama (EvidenceService).
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } = await this.evidenceService.loadAndAggregate(
        tx,
        normalizedAnswers,
      );

      // 8. Insert AssessmentAnswer (bulk), sekalian hitung pointsEarned
      // per jawaban dari map yang sudah di-load di step 4.
      await tx.assessmentAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          pointsEarned: a.isCorrect ? (pointsByQuestionId.get(a.questionId) ?? 0) : 0,
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
        totalPossiblePoints > 0 ? (totalEarnedPoints / totalPossiblePoints) * 100 : 0;

      // Sesi 6: deteksi timing mencurigakan -- pola identik dengan
      // DiagnosticsService, fungsi pure yang sama-sama di-reuse.
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      const updatedAttempt = await tx.assessmentAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(timingCheck.isFlagged
            ? {
                isFlagged: true,
                flagReason: timingCheck.flagReason,
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
}
