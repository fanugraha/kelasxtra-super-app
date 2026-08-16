import { calculateConfidence } from './confidence-calculator';

describe('calculateConfidence', () => {
  const K = 5;

  it.each([
    [1, 18],
    [2, 33],
    [5, 63],
    [10, 86],
    [15, 95],
    [20, 98],
  ])('totalAnswered=%i menghasilkan kira-kira %i%%', (totalAnswered, expectedPercent) => {
    const result = calculateConfidence(totalAnswered, K);
    expect(Math.round(result * 100)).toBe(expectedPercent);
  });

  it('totalAnswered=0 menghasilkan confidence 0', () => {
    expect(calculateConfidence(0, K)).toBe(0);
  });

  it('melempar error kalau totalAnswered negatif', () => {
    expect(() => calculateConfidence(-1, K)).toThrow();
  });

  it('mendekati 1 tapi tidak pernah benar-benar 1 (asymptotic)', () => {
    const result = calculateConfidence(100, K);
    expect(result).toBeLessThan(1);
    expect(result).toBeGreaterThan(0.99);
  });
});
