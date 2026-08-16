import { aggregateEvidence, OptionLookup } from './evidence-aggregator';

describe('aggregateEvidence', () => {
  it('menghitung isCorrect dari optionLookup (per-question) dan mengelompokkan evidence per competency', () => {
    const questionLookup = new Map([
      [1, { competencyId: 100, difficulty: 'EASY' as const }],
      [2, { competencyId: 100, difficulty: 'HARD' as const }],
      [3, { competencyId: 200, difficulty: 'MEDIUM' as const }],
    ]);
    const optionLookup = new Map<number, OptionLookup>([
      [11, { questionId: 1, isCorrect: true }],
      [21, { questionId: 2, isCorrect: false }],
      [32, { questionId: 3, isCorrect: true }],
    ]);

    const result = aggregateEvidence(
      [
        { questionId: 1, selectedOptionId: 11 }, // benar
        { questionId: 2, selectedOptionId: 21 }, // salah
        { questionId: 3, selectedOptionId: 32 }, // benar
      ],
      questionLookup,
      optionLookup,
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
    const questionLookup = new Map([
      [1, { competencyId: 100, difficulty: 'EASY' as const }],
    ]);

    const result = aggregateEvidence(
      [{ questionId: 1, selectedOptionId: null }],
      questionLookup,
      new Map(),
    );

    expect(result.enrichedAnswers[0].isCorrect).toBe(false);
  });

  it('question tanpa competency tetap masuk enrichedAnswers tapi tidak masuk evidenceByCompetency', () => {
    const questionLookup = new Map([
      [1, { competencyId: null, difficulty: 'EASY' as const }],
    ]);
    const optionLookup = new Map<number, OptionLookup>([
      [5, { questionId: 1, isCorrect: true }],
    ]);

    const result = aggregateEvidence(
      [{ questionId: 1, selectedOptionId: 5 }],
      questionLookup,
      optionLookup,
    );

    expect(result.enrichedAnswers).toHaveLength(1);
    expect(result.evidenceByCompetency.size).toBe(0);
  });

  it('melempar error kalau ada questionId yang tidak ada di lookup', () => {
    expect(() =>
      aggregateEvidence(
        [{ questionId: 999, selectedOptionId: 1 }],
        new Map(),
        new Map(),
      ),
    ).toThrow();
  });

  // Regression test untuk Bug #1 (QA audit 16 Agustus 2026): sebelum fix,
  // sistem cuma cek "apakah optionId ini benar untuk soal MANAPUN" lewat
  // Set global, jadi satu optionId benar bisa "dipakai ulang" untuk soal
  // lain dan dianggap benar juga. Test ini membuktikan itu SEKARANG DITOLAK.
  describe('Bug #1 fix: option harus milik question yang sedang dijawab', () => {
    it('optionId benar untuk question 1, dikirim ulang sebagai jawaban question 2 -> DITOLAK (bukan dianggap benar)', () => {
      const questionLookup = new Map([
        [1, { competencyId: 100, difficulty: 'EASY' as const }],
        [2, { competencyId: 100, difficulty: 'EASY' as const }],
      ]);
      // optionId 11 adalah jawaban BENAR untuk question 1 saja.
      const optionLookup = new Map<number, OptionLookup>([
        [11, { questionId: 1, isCorrect: true }],
      ]);

      const result = aggregateEvidence(
        [
          { questionId: 1, selectedOptionId: 11 }, // benar-benar milik question 1 -> benar
          { questionId: 2, selectedOptionId: 11 }, // exploit: pakai optionId question 1 untuk question 2
        ],
        questionLookup,
        optionLookup,
      );

      expect(result.enrichedAnswers[0].isCorrect).toBe(true);
      expect(result.enrichedAnswers[1].isCorrect).toBe(false); // HARUS salah, bukan ikut benar
    });

    it('optionId benar tapi dikirim untuk question yang sama sekali tidak terhubung ke option itu -> tetap salah', () => {
      const questionLookup = new Map([
        [5, { competencyId: 300, difficulty: 'MEDIUM' as const }],
        [6, { competencyId: 300, difficulty: 'MEDIUM' as const }],
      ]);
      const optionLookup = new Map<number, OptionLookup>([
        [99, { questionId: 5, isCorrect: true }],
      ]);

      const result = aggregateEvidence(
        [{ questionId: 6, selectedOptionId: 99 }],
        questionLookup,
        optionLookup,
      );

      expect(result.enrichedAnswers[0].isCorrect).toBe(false);
    });
  });
});
