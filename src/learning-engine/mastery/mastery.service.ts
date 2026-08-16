import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { calculateWeightedAccuracy, calculateMasteryEma } from './mastery-calculator';
import { calculateConfidence } from './confidence-calculator';
import { classifyMasteryBucket } from './mastery-classifier';
import { AnswerEvidence, LearningEngineConfigValues, MasteryBucket } from '../learning-engine.types';

export interface UpdateCompetencyInput {
  studentId: number;
  competencyId: number;
  evidence: AnswerEvidence[]; // evidence dari SATU attempt ini saja, bukan seluruh history
  config: LearningEngineConfigValues;
}

export interface UpdateCompetencyResult {
  studentId: number;
  competencyId: number;
  attemptAccuracy: number;
  oldMasteryScore: number | null;
  newMasteryScore: number;
  newConfidenceScore: number;
  totalAnswered: number;
  totalCorrect: number;
  oldBucket: MasteryBucket;
  newBucket: MasteryBucket;
  bucketChanged: boolean;
}

/**
 * Inti dari incremental update (spec Phase 4 bagian 3 & 8): SATU baris
 * StudentCompetency di-baca, dihitung ulang pakai EMA (bukan recompute dari
 * seluruh history jawaban), lalu ditulis lagi. Tidak pernah melakukan
 * SELECT ke seluruh historical answers.
 */
@Injectable()
export class MasteryService {
  async updateForCompetency(
    tx: Prisma.TransactionClient,
    input: UpdateCompetencyInput,
  ): Promise<UpdateCompetencyResult> {
    const { studentId, competencyId, evidence, config } = input;

    if (evidence.length === 0) {
      throw new Error('updateForCompetency: evidence tidak boleh kosong.');
    }

    const existing = await tx.studentCompetency.findUnique({
      where: { studentId_competencyId: { studentId, competencyId } },
    });

    const attemptAccuracy = calculateWeightedAccuracy(evidence, config);
    const correctCount = evidence.filter((e) => e.isCorrect).length;

    const oldMasteryScore = existing ? Number(existing.masteryScore) : null;
    const oldBucket = (existing?.masteryBucket ?? 'INSUFFICIENT_DATA') as MasteryBucket;

    const newTotalAnswered = (existing?.totalAnswered ?? 0) + evidence.length;
    const newTotalCorrect = (existing?.totalCorrect ?? 0) + correctCount;

    const newMasteryScore = calculateMasteryEma(oldMasteryScore, attemptAccuracy, config.alpha);
    const newConfidenceScore = calculateConfidence(newTotalAnswered, config.confidenceK);
    const newBucket = classifyMasteryBucket(newMasteryScore, newConfidenceScore, config);

    await tx.studentCompetency.upsert({
      where: { studentId_competencyId: { studentId, competencyId } },
      create: {
        studentId,
        competencyId,
        totalAnswered: newTotalAnswered,
        totalCorrect: newTotalCorrect,
        masteryScore: newMasteryScore,
        confidenceScore: newConfidenceScore,
        masteryBucket: newBucket,
        lastAttemptAt: new Date(),
      },
      update: {
        totalAnswered: newTotalAnswered,
        totalCorrect: newTotalCorrect,
        masteryScore: newMasteryScore,
        confidenceScore: newConfidenceScore,
        masteryBucket: newBucket,
        lastAttemptAt: new Date(),
      },
    });

    return {
      studentId,
      competencyId,
      attemptAccuracy,
      oldMasteryScore,
      newMasteryScore,
      newConfidenceScore,
      totalAnswered: newTotalAnswered,
      totalCorrect: newTotalCorrect,
      oldBucket,
      newBucket,
      bucketChanged: oldBucket !== newBucket,
    };
  }
}
