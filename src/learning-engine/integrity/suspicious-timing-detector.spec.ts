import { detectSuspiciousTiming } from './suspicious-timing-detector';

describe('detectSuspiciousTiming', () => {
  it('tidak flag kalau data waktu kurang dari 3 jawaban', () => {
    const result = detectSuspiciousTiming([
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 1 },
    ]);
    expect(result.isFlagged).toBe(false);
    expect(result.flagReason).toBeNull();
  });

  it('flag kalau >=50% jawaban (dengan cukup sampel) terlalu cepat', () => {
    const result = detectSuspiciousTiming([
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 30 },
    ]);
    expect(result.isFlagged).toBe(true);
    expect(result.flagReason).toContain('3 dari 4');
  });

  it('tidak flag kalau mayoritas jawaban wajar', () => {
    const result = detectSuspiciousTiming([
      { timeSpentSeconds: 20 },
      { timeSpentSeconds: 25 },
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 30 },
    ]);
    expect(result.isFlagged).toBe(false);
  });

  it('mengabaikan jawaban tanpa data waktu (null/undefined)', () => {
    const result = detectSuspiciousTiming([
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: 1 },
      { timeSpentSeconds: null },
      { timeSpentSeconds: undefined },
    ]);
    // 3 jawaban dengan data waktu, semuanya cepat -> tetap flagged
    expect(result.isFlagged).toBe(true);
  });

  it('jawaban tepat di ambang (2 detik) tidak dihitung "terlalu cepat"', () => {
    const result = detectSuspiciousTiming([
      { timeSpentSeconds: 2 },
      { timeSpentSeconds: 2 },
      { timeSpentSeconds: 2 },
    ]);
    expect(result.isFlagged).toBe(false);
  });
});
