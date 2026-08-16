import { BadRequestException } from '@nestjs/common';
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

// Dulu cuma Set<number> dari option ID yang "benar" secara GLOBAL — itu yang
// jadi celah Bug #1 (lihat evidence.service.ts). Sekarang per-option kita
// tahu dia MILIK question mana, supaya bisa divalidasi option itu benar
// UNTUK SOAL YANG SEDANG DIJAWAB, bukan cuma "benar untuk soal manapun".
export interface OptionLookup {
  questionId: number;
  isCorrect: boolean;
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
 *
 * KEAMANAN (fix Bug #1): sebuah selectedOptionId dianggap benar HANYA kalau
 * option itu benar-benar milik questionId yang sedang dijawab DAN isCorrect
 * true. Sebelumnya sistem cuma cek "apakah option ID ini benar untuk soal
 * manapun" (Set global) — itu memungkinkan siswa mengirim satu optionId
 * yang benar untuk SEMUA soal lain dalam payload dan dianggap semuanya benar.
 */
export function aggregateEvidence(
  rawAnswers: RawSubmittedAnswer[],
  questionLookup: Map<number, QuestionLookup>,
  optionLookup: Map<number, OptionLookup>,
): EvidenceAggregationResult {
  const enrichedAnswers: EnrichedAnswer[] = [];
  const evidenceByCompetency = new Map<number, AnswerEvidence[]>();

  for (const raw of rawAnswers) {
    const question = questionLookup.get(raw.questionId);

    if (!question) {
      throw new BadRequestException(
        `Question ${raw.questionId} tidak ditemukan.`,
      );
    }

    let isCorrect = false;
    if (raw.selectedOptionId !== null) {
      const option = optionLookup.get(raw.selectedOptionId);
      // option harus ada DAN benar-benar milik question ini -- inilah inti
      // fix-nya. Kalau siswa kirim optionId dari soal lain, option.questionId
      // tidak akan cocok dengan raw.questionId, jadi tetap dianggap salah.
      isCorrect =
        !!option && option.questionId === raw.questionId && option.isCorrect;
    }

    const enriched: EnrichedAnswer = {
      ...raw,
      isCorrect,
      difficulty: question.difficulty,
      competencyId: question.competencyId,
    };
    enrichedAnswers.push(enriched);

    if (question.competencyId !== null) {
      const evidenceList =
        evidenceByCompetency.get(question.competencyId) ?? [];
      evidenceList.push({ difficulty: question.difficulty, isCorrect });
      evidenceByCompetency.set(question.competencyId, evidenceList);
    }
  }

  return { enrichedAnswers, evidenceByCompetency };
}
