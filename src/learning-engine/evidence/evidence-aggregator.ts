import { AnswerEvidence, Difficulty } from '../learning-engine.types';

export interface RawSubmittedAnswer {
  questionId: number;
  selectedOptionId: number | null;
  timeSpentSeconds?: number | null;
}

export interface QuestionLookup {
  competencyId: number | null;
  difficulty: Difficulty;
}

export interface EnrichedAnswer extends RawSubmittedAnswer {
  isCorrect: boolean;
  difficulty: Difficulty;
  competencyId: number | null;
}

export interface EvidenceAggregationResult {
  enrichedAnswers: EnrichedAnswer[];
  evidenceByCompetency: Map<number, AnswerEvidence[]>;
}

/**
 * Gabungkan raw submitted answers dengan data question/option yang SUDAH
 * di-batch-load sebelumnya (lihat EvidenceService), lalu kelompokkan
 * evidence per competency. Fungsi ini murni — tidak menyentuh Prisma sama
 * sekali — supaya gampang di-unit-test tanpa database.
 *
 * Soal yang tidak terhubung ke competency manapun (competencyId null) tetap
 * masuk ke enrichedAnswers (untuk disimpan sebagai jawaban), tapi TIDAK ikut
 * dikelompokkan ke evidenceByCompetency karena tidak ada mastery yang perlu
 * di-update untuknya.
 */
export function aggregateEvidence(
  rawAnswers: RawSubmittedAnswer[],
  questionLookup: Map<number, QuestionLookup>,
  correctOptionIds: Set<number>,
): EvidenceAggregationResult {
  const enrichedAnswers: EnrichedAnswer[] = [];
  const evidenceByCompetency = new Map<number, AnswerEvidence[]>();

  for (const raw of rawAnswers) {
    const question = questionLookup.get(raw.questionId);

    if (!question) {
      throw new Error(`aggregateEvidence: question ${raw.questionId} tidak ditemukan.`);
    }

    const isCorrect = raw.selectedOptionId !== null && correctOptionIds.has(raw.selectedOptionId);

    const enriched: EnrichedAnswer = {
      ...raw,
      isCorrect,
      difficulty: question.difficulty,
      competencyId: question.competencyId,
    };
    enrichedAnswers.push(enriched);

    if (question.competencyId !== null) {
      const evidenceList = evidenceByCompetency.get(question.competencyId) ?? [];
      evidenceList.push({ difficulty: question.difficulty, isCorrect });
      evidenceByCompetency.set(question.competencyId, evidenceList);
    }
  }

  return { enrichedAnswers, evidenceByCompetency };
}
