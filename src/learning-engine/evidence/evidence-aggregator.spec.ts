import { aggregateEvidence } from './evidence-aggregator';

describe('aggregateEvidence', () => {
  it('menghitung isCorrect dari correctOptionIds dan mengelompokkan evidence per competency', () => {
    const questionLookup = new Map([
      [1, { competencyId: 100, difficulty: 'EASY' as const }],
      [2, { competencyId: 100, difficulty: 'HARD' as const }],
      [3, { competencyId: 200, difficulty: 'MEDIUM' as const }],
    ]);
    const correctOptionIds = new Set([11, 32]);

    const result = aggregateEvidence(
      [
        { questionId: 1, selectedOptionId: 11 }, // benar
        { questionId: 2, selectedOptionId: 21 }, // salah
        { questionId: 3, selectedOptionId: 32 }, // benar
      ],
      questionLookup,
      correctOptionIds,
    );

    expect(result.enrichedAnswers).toHaveLength(3);
    expect(result.enrichedAnswers[0].isCorrect).toBe(true);
    expect(result.enrichedAnswers[1].isCorrect).toBe(false);
    expect(result.enrichedAnswers[2].isCorrect).toBe(true);

    expect(result.evidenceByCompetency.get(100)).toEqual([
      { difficulty: 'EASY', isCorrect: true },
      { difficulty: 'HARD', isCorrect: false },
    ]);
    expect(result.evidenceByCompetency.get(200)).toEqual([
      { difficulty: 'MEDIUM', isCorrect: true },
    ]);
  });

  it('selectedOptionId null (soal tidak dijawab) dianggap salah', () => {
    const questionLookup = new Map([[1, { competencyId: 100, difficulty: 'EASY' as const }]]);

    const result = aggregateEvidence(
      [{ questionId: 1, selectedOptionId: null }],
      questionLookup,
      new Set(),
    );

    expect(result.enrichedAnswers[0].isCorrect).toBe(false);
  });

  it('question tanpa competency tetap masuk enrichedAnswers tapi tidak masuk evidenceByCompetency', () => {
    const questionLookup = new Map([[1, { competencyId: null, difficulty: 'EASY' as const }]]);

    const result = aggregateEvidence(
      [{ questionId: 1, selectedOptionId: 5 }],
      questionLookup,
      new Set([5]),
    );

    expect(result.enrichedAnswers).toHaveLength(1);
    expect(result.evidenceByCompetency.size).toBe(0);
  });

  it('melempar error kalau ada questionId yang tidak ada di lookup', () => {
    expect(() =>
      aggregateEvidence([{ questionId: 999, selectedOptionId: 1 }], new Map(), new Set()),
    ).toThrow();
  });
});
