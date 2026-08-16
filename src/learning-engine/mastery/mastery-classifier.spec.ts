import { classifyMasteryBucket } from './mastery-classifier';

const THRESHOLDS = {
  masteredThreshold: 80,
  developingThreshold: 60,
  minimumConfidence: 0.6,
};

describe('classifyMasteryBucket', () => {
  it('confidence rendah -> INSUFFICIENT_DATA, walaupun masteryScore tinggi', () => {
    // Ini kasus penting: mastery kelihatan bagus tapi baru dari 1-2 soal,
    // sistem belum boleh percaya penuh.
    const result = classifyMasteryBucket(95, 0.2, THRESHOLDS);
    expect(result).toBe('INSUFFICIENT_DATA');
  });

  it('confidence cukup + mastery di bawah developingThreshold -> LEARNING_GAP', () => {
    const result = classifyMasteryBucket(45, 0.8, THRESHOLDS);
    expect(result).toBe('LEARNING_GAP');
  });

  it('confidence cukup + mastery di antara threshold -> DEVELOPING', () => {
    const result = classifyMasteryBucket(72, 0.8, THRESHOLDS);
    expect(result).toBe('DEVELOPING');
  });

  it('confidence cukup + mastery >= masteredThreshold -> MASTERED', () => {
    const result = classifyMasteryBucket(85, 0.8, THRESHOLDS);
    expect(result).toBe('MASTERED');
  });

  it('confidence tepat di batas minimum dianggap cukup (bukan INSUFFICIENT_DATA)', () => {
    const result = classifyMasteryBucket(85, 0.6, THRESHOLDS);
    expect(result).toBe('MASTERED');
  });

  it('mastery tepat di batas developingThreshold dianggap DEVELOPING (bukan LEARNING_GAP)', () => {
    const result = classifyMasteryBucket(60, 0.8, THRESHOLDS);
    expect(result).toBe('DEVELOPING');
  });
});
