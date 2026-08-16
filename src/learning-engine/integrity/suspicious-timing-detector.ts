/**
 * Deteksi kecurangan sederhana berbasis timing, rule-based (bukan ML) sesuai
 * prinsip V1. Fungsi ini murni -- tidak menyentuh Prisma -- supaya gampang
 * di-unit-test tanpa database, mengikuti pola mastery-calculator.ts.
 */

export interface TimedAnswer {
  timeSpentSeconds: number | null | undefined;
}

export interface SuspiciousTimingResult {
  isFlagged: boolean;
  flagReason: string | null;
}

// Jawaban di bawah ambang ini (detik) dianggap "terlalu cepat untuk dibaca
// dan dijawab dengan wajar".
export const MIN_SECONDS_PER_ANSWER = 2;

// Kalau proporsi jawaban-cepat terhadap jawaban-yang-punya-data-waktu
// mencapai ambang ini, attempt ditandai.
export const SUSPICIOUS_RATIO_THRESHOLD = 0.5;

// Jangan menyimpulkan kecurangan dari sampel terlalu kecil.
export const MIN_TIMED_ANSWERS_FOR_EVALUATION = 3;

export function detectSuspiciousTiming(answers: TimedAnswer[]): SuspiciousTimingResult {
  const timedAnswers = answers.filter(
    (a): a is { timeSpentSeconds: number } =>
      typeof a.timeSpentSeconds === 'number' && a.timeSpentSeconds >= 0,
  );

  if (timedAnswers.length < MIN_TIMED_ANSWERS_FOR_EVALUATION) {
    return { isFlagged: false, flagReason: null };
  }

  const fastCount = timedAnswers.filter(
    (a) => a.timeSpentSeconds < MIN_SECONDS_PER_ANSWER,
  ).length;
  const fastRatio = fastCount / timedAnswers.length;

  if (fastRatio >= SUSPICIOUS_RATIO_THRESHOLD) {
    return {
      isFlagged: true,
      flagReason: `${fastCount} dari ${timedAnswers.length} jawaban (${Math.round(
        fastRatio * 100,
      )}%) dijawab dalam waktu kurang dari ${MIN_SECONDS_PER_ANSWER} detik.`,
    };
  }

  return { isFlagged: false, flagReason: null };
}
