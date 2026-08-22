#!/bin/bash
set -e
echo ">> Fix: pengecekan duplicate questionId (Bug #2) hilang lagi dari diagnostics.service.ts di tengah beberapa kali rewrite -- exploit tetap tertahan (lapisan unique constraint di database masih jalan), tapi status code-nya salah (409 padahal seharusnya 400). Dikembalikan persis sama polanya dengan AssessmentsService."

mkdir -p "$(dirname "src/diagnostics/diagnostics.service.ts")"
echo ">> Menulis src/diagnostics/diagnostics.service.ts"
cat > src/diagnostics/diagnostics.service.ts << 'KELASXTRA_FIX_BUG2_MISSING_CHECK_21AUG'
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
import { CreateDiagnosticTestDto } from './dto/create-diagnostic-test.dto';
import { detectSuspiciousTiming } from '../learning-engine/integrity/suspicious-timing-detector';

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

  // Keputusan bisnis (16 Agustus 2026): diagnostic test itu "titik awal"
  // (starting point) buat learning path siswa, BUKAN latihan yang boleh
  // diulang bebas -- kalau boleh diulang tanpa batas, siswa bisa "diagnostic
  // shopping" (coba berkali-kali sampai dapat hasil yang menguntungkan).
  // Assessment TIDAK kena aturan ini (lihat AssessmentsService) -- itu
  // memang harus boleh diulang, beda peran dengan diagnostic.
  //
  // diagnosticTest.allowMultipleAttempts (default false) bisa override
  // cap ini per-test tanpa migration/rewrite lagi -- lihat komentar di
  // schema.prisma (forward-compat untuk Teacher Engine).
  async startAttempt(userId: number, diagnosticTestId: number) {
    const profile = await this.findProfileByUserId(userId);

    const diagnosticTest = await this.prisma.diagnosticTest.findUnique({
      where: { id: diagnosticTestId },
    });

    if (!diagnosticTest) {
      throw new NotFoundException('Diagnostic test tidak ditemukan.');
    }

    const latestAttempt = await this.prisma.diagnosticAttempt.findFirst({
      where: { diagnosticTestId, studentId: profile.id },
      orderBy: { startedAt: 'desc' },
    });

    if (!diagnosticTest.allowMultipleAttempts && latestAttempt?.status === 'SUBMITTED') {
      throw new ConflictException(
        'Kamu sudah menyelesaikan diagnostic test ini. Diagnostic test hanya bisa dikerjakan sekali -- hubungi guru/admin kalau butuh mengulang.',
      );
    }

    // Attempt lama masih IN_PROGRESS (mis. tab ditutup sebelum submit) --
    // lanjutkan attempt yang sama, jangan bikin duplikat. Berlaku baik
    // cap-nya aktif maupun tidak.
    if (latestAttempt?.status === 'IN_PROGRESS') {
      return latestAttempt;
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

  // ADMIN/TEACHER only (ditegakkan di controller lewat @Roles). "Void"
  // dipilih daripada delete supaya riwayat attempt asli tetap bisa
  // ditelusuri -- siapa yang reset, kapan, dan alasannya apa.
  async voidAttempt(actorUserId: number, attemptId: number, reason?: string) {
    const attempt = await this.prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });

    if (!attempt) {
      throw new NotFoundException('Attempt tidak ditemukan.');
    }

    if (attempt.status === 'VOID') {
      throw new ConflictException('Attempt ini sudah di-void sebelumnya.');
    }

    return this.prisma.diagnosticAttempt.update({
      where: { id: attemptId },
      data: {
        status: 'VOID',
        voidedAt: new Date(),
        voidReason: reason,
        voidedByUserId: actorUserId,
      },
    });
  }

  // Gap Phase 4 (19 Agustus 2026): sebelum ini TIDAK ADA endpoint sama
  // sekali untuk membuat DiagnosticTest baru -- satu-satunya cara cuma
  // lewat seed script manual. ADMIN-only karena DiagnosticTest tidak
  // punya teacherId di schema (platform-level, bukan milik teacher
  // tertentu) -- konsisten dengan section 5.4 dokumen master.
  async createTest(dto: CreateDiagnosticTestDto) {
    const subject = await this.prisma.subject.findUnique({ where: { id: dto.subjectId } });
    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    const uniqueQuestionIds = [...new Set(dto.questionIds)];
    const questions = await this.prisma.question.findMany({
      where: { id: { in: uniqueQuestionIds } },
    });
    if (questions.length !== uniqueQuestionIds.length) {
      throw new BadRequestException('Ada questionId yang tidak valid/tidak ditemukan.');
    }

    return this.prisma.diagnosticTest.create({
      data: {
        subjectId: dto.subjectId,
        name: dto.name,
        durationMinutes: dto.durationMinutes,
        allowMultipleAttempts: dto.allowMultipleAttempts ?? false,
        questions: {
          create: uniqueQuestionIds.map((questionId, index) => ({
            questionId,
            sequence: index,
          })),
        },
      },
      include: { questions: true },
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
      // bagian dari diagnostic test ini (bukan soal dari test lain). Juga
      // tolak questionId yang dikirim berulang dalam satu payload (fix
      // Bug #2 QA audit 16 Agustus 2026 -- sempat hilang lagi dari file
      // ini di tengah beberapa kali rewrite, cuma ketahan lapisan
      // database (unique constraint) yang balikin 409, bukan 400 yang
      // seharusnya -- exploit-nya tetap tertahan, cuma status code-nya
      // salah. Pola sama persis dengan AssessmentsService.).
      const validQuestions = await tx.diagnosticQuestion.findMany({
        where: { diagnosticTestId },
        select: { questionId: true },
      });
      const validQuestionIds = new Set(validQuestions.map((q) => q.questionId));
      const seenQuestionIds = new Set<number>();

      for (const answer of dto.answers) {
        if (!validQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari diagnostic test ini.`,
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

      // Sesi 6: deteksi timing mencurigakan -- rule-based, murni fungsi,
      // dievaluasi dari jawaban attempt ini saja.
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      // Keputusan bisnis (16 Agustus 2026, item #3): durationMinutes DITEGAKKAN
      // sebagai SOFT FLAG, bukan blokir keras -- attempt yang telat tetap
      // diterima & tetap dihitung skornya (siswa tidak dihukum kalau
      // internetnya lelet), tapi ditandai isFlagged supaya guru/admin bisa
      // menilai sendiri lewat data, bukan lewat sistem yang menolak mentah-mentah.
      const diagnosticTest = await tx.diagnosticTest.findUnique({
        where: { id: diagnosticTestId },
        select: { durationMinutes: true },
      });
      const elapsedMinutes = (Date.now() - attempt.startedAt.getTime()) / 60_000;
      const isOverDuration =
        diagnosticTest?.durationMinutes != null &&
        elapsedMinutes > diagnosticTest.durationMinutes;

      const flagReasons = [
        ...(timingCheck.isFlagged && timingCheck.flagReason ? [timingCheck.flagReason] : []),
        ...(isOverDuration
          ? [
              `Melebihi batas waktu pengerjaan (${diagnosticTest!.durationMinutes} menit, selesai dalam ${Math.round(elapsedMinutes)} menit).`,
            ]
          : []),
      ];
      const isFlagged = timingCheck.isFlagged || isOverDuration;

      const updatedAttempt = await tx.diagnosticAttempt.update({
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
}
KELASXTRA_FIX_BUG2_MISSING_CHECK_21AUG

echo ""
echo ">> Selesai. Tidak ada perubahan schema/DTO."
echo "Langkah selanjutnya: npm run test:e2e"
