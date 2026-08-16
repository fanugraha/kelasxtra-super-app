import { LearningEngineConfigValues, MasteryBucket } from '../learning-engine.types';

/**
 * Klasifikasi mastery ke salah satu dari 4 bucket. Confidence gate ada DULU
 * sebelum threshold mastery — ini yang mencegah sistem langsung memvonis
 * "learning gap" hanya dari 1-2 jawaban.
 *
 *   confidence < minimumConfidence        -> INSUFFICIENT_DATA
 *   else mastery < developingThreshold    -> LEARNING_GAP
 *   else mastery < masteredThreshold      -> DEVELOPING
 *   else                                   -> MASTERED
 */
export function classifyMasteryBucket(
  masteryScore: number,
  confidenceScore: number,
  config: Pick<
    LearningEngineConfigValues,
    'masteredThreshold' | 'developingThreshold' | 'minimumConfidence'
  >,
): MasteryBucket {
  if (confidenceScore < config.minimumConfidence) {
    return 'INSUFFICIENT_DATA';
  }

  if (masteryScore < config.developingThreshold) {
    return 'LEARNING_GAP';
  }

  if (masteryScore < config.masteredThreshold) {
    return 'DEVELOPING';
  }

  return 'MASTERED';
}
