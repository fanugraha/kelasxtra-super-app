import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { EvidenceSourceType, MasteryBucket } from '../learning-engine.types';

export interface CreateSnapshotInput {
  studentId: number;
  competencyId: number;
  masteryScore: number;
  confidenceScore: number;
  totalAnswered: number;
  totalCorrect: number;
  masteryBucket: MasteryBucket;
  triggeredByAttemptId: number;
  sourceType: EvidenceSourceType;
  engineVersion: number;
  configVersion: number;
}

/**
 * CompetencySnapshot bersifat APPEND-ONLY (spec Phase 4, bagian 4 & 24).
 * Service ini sengaja HANYA punya method create — tidak ada update/delete —
 * supaya tidak ada jalan pintas di kode lain yang melanggar aturan itu.
 */
@Injectable()
export class CompetencySnapshotService {
  async create(tx: Prisma.TransactionClient, input: CreateSnapshotInput) {
    return tx.competencySnapshot.create({
      data: {
        studentId: input.studentId,
        competencyId: input.competencyId,
        masteryScore: input.masteryScore,
        confidenceScore: input.confidenceScore,
        totalAnswered: input.totalAnswered,
        totalCorrect: input.totalCorrect,
        masteryBucket: input.masteryBucket,
        triggeredByAttemptId: input.triggeredByAttemptId,
        sourceType: input.sourceType,
        engineVersion: input.engineVersion,
        configVersion: input.configVersion,
      },
    });
  }
}
