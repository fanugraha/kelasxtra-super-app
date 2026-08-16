import { AnswerEvidence, LearningEngineConfigValues } from '../learning-engine.types';

/**
 * Menghitung attemptAccuracy dari satu attempt, dibobot berdasarkan difficulty
 * tiap soal (bukan sekadar persentase benar/salah polos).
 *
 * weightedCorrect = jumlah weight soal yang dijawab benar
 * weightedTotal   = jumlah weight seluruh soal yang dijawab
 * attemptAccuracy = (weightedCorrect / weightedTotal) * 100
 *
 * Contoh dari spec: EASY benar (1.0) + MEDIUM benar (1.5) + HARD salah (2.0 di total, 0 di correct)
 *   → weightedCorrect = 2.5, weightedTotal = 4.5 → attemptAccuracy = 55.56
 */
export function calculateWeightedAccuracy(
  answers: AnswerEvidence[],
  config: Pick<
    LearningEngineConfigValues,
    'difficultyEasyWeight' | 'difficultyMediumWeight' | 'difficultyHardWeight'
  >,
): number {
  if (answers.length === 0) {
    throw new Error('calculateWeightedAccuracy: answers tidak boleh kosong.');
  }

  const weightByDifficulty: Record<string, number> = {
    EASY: config.difficultyEasyWeight,
    MEDIUM: config.difficultyMediumWeight,
    HARD: config.difficultyHardWeight,
  };

  let weightedCorrect = 0;
  let weightedTotal = 0;

  for (const answer of answers) {
    const weight = weightByDifficulty[answer.difficulty];
    weightedTotal += weight;
    if (answer.isCorrect) {
      weightedCorrect += weight;
    }
  }

  return (weightedCorrect / weightedTotal) * 100;
}

/**
 * Exponential Moving Average untuk masteryScore.
 *
 * First attempt rule: kalau competency ini belum pernah punya evidence
 * (oldMastery === null), JANGAN pakai EMA terhadap nilai nol — langsung
 * pakai attemptAccuracy apa adanya sebagai masteryScore awal.
 *
 * Selain itu:
 *   newMastery = alpha * attemptAccuracy + (1 - alpha) * oldMastery
 */
export function calculateMasteryEma(
  oldMastery: number | null,
  attemptAccuracy: number,
  alpha: number,
): number {
  if (oldMastery === null) {
    return attemptAccuracy;
  }

  return alpha * attemptAccuracy + (1 - alpha) * oldMastery;
}
