export type Difficulty = 'EASY' | 'MEDIUM' | 'HARD';

export type MasteryBucket = 'INSUFFICIENT_DATA' | 'LEARNING_GAP' | 'DEVELOPING' | 'MASTERED';

export type EvidenceSourceType = 'DIAGNOSTIC' | 'ASSESSMENT';

// Satu baris bukti jawaban, dilepas dari row Prisma apa pun (DiagnosticAnswer/AssessmentAnswer)
// supaya calculator-nya nggak perlu tahu soal itu berasal dari tabel mana.
export interface AnswerEvidence {
  difficulty: Difficulty;
  isCorrect: boolean;
}

// Snapshot dari LearningEngineConfig yang lagi active, dipakai semua calculator.
// Dibikin terpisah dari model Prisma-nya biar calculator tetap pure/tidak bergantung ke Prisma.
export interface LearningEngineConfigValues {
  alpha: number;
  difficultyEasyWeight: number;
  difficultyMediumWeight: number;
  difficultyHardWeight: number;
  masteredThreshold: number;
  developingThreshold: number;
  confidenceK: number;
  minimumConfidence: number;
  engineVersion: number;
  configVersion: number;
}
