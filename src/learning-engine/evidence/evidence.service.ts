import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import {
  aggregateEvidence,
  EvidenceAggregationResult,
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
      ...new Set(rawAnswers.map((a) => a.selectedOptionId).filter((id): id is number => id !== null)),
    ];

    const [questions, correctOptions] = await Promise.all([
      tx.question.findMany({
        where: { id: { in: questionIds } },
        select: { id: true, competencyId: true, difficulty: true },
      }),
      selectedOptionIds.length > 0
        ? tx.questionOption.findMany({
            where: { id: { in: selectedOptionIds }, isCorrect: true },
            select: { id: true },
          })
        : Promise.resolve([]),
    ]);

    const questionLookup = new Map<number, QuestionLookup>(
      questions.map((q) => [
        q.id,
        { competencyId: q.competencyId, difficulty: q.difficulty as Difficulty },
      ]),
    );

    const correctOptionIds = new Set(correctOptions.map((o) => o.id));

    return aggregateEvidence(rawAnswers, questionLookup, correctOptionIds);
  }
}
