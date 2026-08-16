import { calculateWeightedAccuracy, calculateMasteryEma } from './mastery-calculator';

const DIFFICULTY_WEIGHTS = {
  difficultyEasyWeight: 1.0,
  difficultyMediumWeight: 1.5,
  difficultyHardWeight: 2.0,
};

describe('calculateWeightedAccuracy', () => {
  it('menghitung sesuai contoh di spec: EASY benar, MEDIUM benar, HARD salah', () => {
    const result = calculateWeightedAccuracy(
      [
        { difficulty: 'EASY', isCorrect: true },
        { difficulty: 'MEDIUM', isCorrect: true },
        { difficulty: 'HARD', isCorrect: false },
      ],
      DIFFICULTY_WEIGHTS,
    );

    expect(result).toBeCloseTo(55.56, 1);
  });

  it('menghasilkan 100 kalau semua jawaban benar', () => {
    const result = calculateWeightedAccuracy(
      [
        { difficulty: 'EASY', isCorrect: true },
        { difficulty: 'HARD', isCorrect: true },
      ],
      DIFFICULTY_WEIGHTS,
    );

    expect(result).toBe(100);
  });

  it('menghasilkan 0 kalau semua jawaban salah', () => {
    const result = calculateWeightedAccuracy(
      [{ difficulty: 'MEDIUM', isCorrect: false }],
      DIFFICULTY_WEIGHTS,
    );

    expect(result).toBe(0);
  });

  it('melempar error kalau answers kosong', () => {
    expect(() => calculateWeightedAccuracy([], DIFFICULTY_WEIGHTS)).toThrow();
  });
});

describe('calculateMasteryEma', () => {
  it('first attempt: langsung pakai attemptAccuracy, bukan EMA terhadap nol', () => {
    const result = calculateMasteryEma(null, 100, 0.3);
    expect(result).toBe(100);
  });

  it('sesuai contoh spec: oldMastery=100, attemptAccuracy=40, alpha=0.3 -> 82', () => {
    const result = calculateMasteryEma(100, 40, 0.3);
    expect(result).toBeCloseTo(82, 5);
  });

  it('attempt buruk berulang menurunkan mastery secara bertahap, bukan langsung jatuh', () => {
    let mastery = calculateMasteryEma(null, 90, 0.3); // 90
    mastery = calculateMasteryEma(mastery, 10, 0.3); // 0.3*10 + 0.7*90 = 66
    expect(mastery).toBeCloseTo(66, 5);
  });
});
