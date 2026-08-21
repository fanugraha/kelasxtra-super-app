#!/bin/bash
set -e
echo ">> Fix bug compile TypeScript: Map constructor tuple-widening di evidence.service.ts (BLOCKING npm run start:dev) dan assessments.service.ts (bug sejenis, sebelumnya dikira non-blocking, ternyata juga blocking)."

mkdir -p "$(dirname "src/learning-engine/evidence/evidence.service.ts")"
echo ">> Menulis src/learning-engine/evidence/evidence.service.ts"
cat > src/learning-engine/evidence/evidence.service.ts << 'KELASXTRA_FIX_TUPLE_WIDENING_19AUG'
import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import {
  aggregateEvidence,
  EvidenceAggregationResult,
  OptionLookup,
  QuestionLookup,
  RawSubmittedAnswer,
} from './evidence-aggregator';
import { Difficulty } from '../learning-engine.types';

@Injectable()
export class EvidenceService {
  /**
   * Batch-load semua question + option yang relevan dalam MAKSIMAL dua
   * query (bukan satu query per jawaban), lalu kelompokkan evidence-nya
   * per competency. Ini yang memenuhi aturan "1 query -> load questions"
   * di spec Phase 4 — jumlah query TIDAK bertambah seiring jumlah jawaban.
   *
   * `tx` wajib berupa Prisma transaction client (bukan this.prisma
   * langsung), supaya batch load ini konsisten dalam transaksi yang sama
   * dengan insert answer / update StudentCompetency di Sesi 4/5 nanti.
   */
  async loadAndAggregate(
    tx: Prisma.TransactionClient,
    rawAnswers: RawSubmittedAnswer[],
  ): Promise<EvidenceAggregationResult> {
    if (rawAnswers.length === 0) {
      return { enrichedAnswers: [], evidenceByCompetency: new Map() };
    }

    const questionIds = [...new Set(rawAnswers.map((a) => a.questionId))];
    const selectedOptionIds = [
      ...new Set(
        rawAnswers
          .map((a) => a.selectedOptionId)
          .filter((id): id is number => id !== null),
      ),
    ];

    const [questions, selectedOptions] = await Promise.all([
      tx.question.findMany({
        where: { id: { in: questionIds } },
        select: { id: true, competencyId: true, difficulty: true },
      }),
      // Fix Bug #1: dulu query ini di-filter `isCorrect: true` lalu hasilnya
      // dijadikan Set<number> global, jadi sistem cuma tahu "option ID ini
      // benar", tanpa tahu benar UNTUK SOAL MANA. Sekarang kita ambil
      // questionId pemilik tiap option (regardless benar/salah) supaya bisa
      // divalidasi option itu benar-benar milik soal yang sedang dijawab.
      selectedOptionIds.length > 0
        ? tx.questionOption.findMany({
            where: { id: { in: selectedOptionIds } },
            select: { id: true, questionId: true, isCorrect: true },
          })
        : Promise.resolve([]),
    ]);

    // Return type eksplisit [number, X] di callback .map() -- tanpa ini,
    // TypeScript kadang melebarkan (widen) array literal jadi tipe non-tuple
    // saat dipakai sebagai argumen `new Map(...)`, yang memicu error
    // "No overload matches this call" di real Prisma types (ini lolos dari
    // pengecekan stub Prisma Client sebelumnya karena stub itu terlalu
    // longgar/`any`, jadi bug tuple-widening ini tidak pernah kelihatan).
    const questionLookup = new Map<number, QuestionLookup>(
      questions.map((q): [number, QuestionLookup] => [
        q.id,
        {
          competencyId: q.competencyId,
          difficulty: q.difficulty as Difficulty,
        },
      ]),
    );

    const optionLookup = new Map<number, OptionLookup>(
      selectedOptions.map((o): [number, OptionLookup] => [
        o.id,
        { questionId: o.questionId, isCorrect: o.isCorrect },
      ]),
    );

    return aggregateEvidence(rawAnswers, questionLookup, optionLookup);
  }
}
KELASXTRA_FIX_TUPLE_WIDENING_19AUG

mkdir -p "$(dirname "src/assessments/assessments.service.ts")"
echo ">> Menulis src/assessments/assessments.service.ts"
cat > src/assessments/assessments.service.ts << 'KELASXTRA_FIX_TUPLE_WIDENING_19AUG'
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
import { CreateAssessmentDto } from './dto/create-assessment.dto';
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
  //
  // Ini DEFAULT fallback -- assessment.cooldownHours (nullable) bisa
  // override per-item kalau nanti Teacher Engine butuh itu, tanpa
  // migration/rewrite lagi (lihat komentar di schema.prisma).
  private static readonly DEFAULT_ATTEMPT_COOLDOWN_HOURS = 24;

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
      const cooldownHours =
        assessment.cooldownHours ??
        AssessmentsService.DEFAULT_ATTEMPT_COOLDOWN_HOURS;
      const hoursSinceLastAttempt =
        (Date.now() - latestAttempt.completedAt.getTime()) / 3_600_000;

      if (hoursSinceLastAttempt < cooldownHours) {
        const hoursRemaining = Math.ceil(cooldownHours - hoursSinceLastAttempt);
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
      // Return type eksplisit [number, number] -- pola yang sama dengan
      // fix di evidence.service.ts (bug tuple-widening yang sama, lolos
      // dari pengecekan sebelumnya karena stub Prisma di sandbox terlalu
      // longgar). Tanpa ini, `totalPossiblePoints += possible` di bawah
      // gagal compile terhadap real Prisma types ("+=' cannot be applied
      // to types 'number' and '{}'").
      const pointsByQuestionId = new Map<number, number>(
        assessmentQuestions.map((q): [number, number] => [q.questionId, Number(q.points)]),
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
        ...(timingCheck.isFlagged && timingCheck.flagReason
          ? [timingCheck.flagReason]
          : []),
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
      ? await this.prisma.assessmentAttempt.findUnique({
          where: { id: attemptId },
        })
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
      throw new BadRequestException(
        'Attempt ini belum disubmit, belum ada hasil.',
      );
    }

    const answers = await this.prisma.assessmentAnswer.findMany({
      where: { attemptId: attempt.id },
      include: {
        question: {
          select: {
            id: true,
            questionText: true,
            difficulty: true,
            competencyId: true,
          },
        },
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

  // Gap Phase 4 (19 Agustus 2026): sebelum ini TIDAK ADA endpoint untuk
  // membuat Assessment baru -- satu-satunya cara cuma lewat seed/fixture
  // manual. TEACHER-only karena Assessment.teacherId wajib diisi di
  // schema (assessment selalu punya pemilik teacher yang jelas).
  async createAssessment(userId: number, dto: CreateAssessmentDto) {
    const profile = await this.prisma.teacherProfile.findUnique({ where: { userId } });
    if (!profile) {
      throw new NotFoundException('Profil teacher tidak ditemukan.');
    }

    const subject = await this.prisma.subject.findUnique({ where: { id: dto.subjectId } });
    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    const questionIds = dto.questions.map((q) => q.questionId);
    const uniqueQuestionIds = [...new Set(questionIds)];
    if (uniqueQuestionIds.length !== questionIds.length) {
      throw new BadRequestException('Ada questionId yang dikirim berulang.');
    }

    const questions = await this.prisma.question.findMany({
      where: { id: { in: uniqueQuestionIds } },
    });
    if (questions.length !== uniqueQuestionIds.length) {
      throw new BadRequestException('Ada questionId yang tidak valid/tidak ditemukan.');
    }

    return this.prisma.assessment.create({
      data: {
        subjectId: dto.subjectId,
        teacherId: profile.id,
        title: dto.title,
        type: dto.type ?? 'FORMATIVE',
        durationMinutes: dto.durationMinutes,
        cooldownHours: dto.cooldownHours,
        questions: {
          create: dto.questions.map((q, index) => ({
            questionId: q.questionId,
            sequence: index,
            points: q.points ?? 1,
          })),
        },
      },
      include: { questions: true },
    });
  }
}
KELASXTRA_FIX_TUPLE_WIDENING_19AUG

echo ""
echo ">> Selesai."
echo "Langkah selanjutnya:"
echo "1. npm run start:dev   # harus compile bersih & server benar-benar nyala sekarang"
echo "2. Kalau start:dev sudah OK, Ctrl+C, lalu: npm run test:e2e"
