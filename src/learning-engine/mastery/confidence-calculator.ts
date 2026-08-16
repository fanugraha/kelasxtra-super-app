/**
 * Confidence score = seberapa yakin sistem terhadap masteryScore yang ada,
 * berdasarkan BANYAKNYA evidence (totalAnswered) — bukan berdasarkan
 * tinggi/rendahnya masteryScore itu sendiri. Mastery rendah dengan confidence
 * rendah berarti "belum cukup bukti", bukan otomatis "pasti learning gap".
 *
 * Fungsi saturasi: confidence naik cepat di awal, melambat sendiri seiring
 * bertambahnya evidence (asymptotic ke 1), jadi tidak perlu banyak breakpoint
 * manual.
 *
 *   confidence = 1 - e^(-totalAnswered / k)
 *
 * Default k = 5. Contoh (k=5): 1 jawaban -> 18%, 5 jawaban -> 63%,
 * 10 jawaban -> 86%, 20 jawaban -> 98%.
 */
export function calculateConfidence(totalAnswered: number, k: number): number {
  if (totalAnswered < 0) {
    throw new Error('calculateConfidence: totalAnswered tidak boleh negatif.');
  }

  return 1 - Math.exp(-totalAnswered / k);
}
