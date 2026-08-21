import { IsIn, IsInt, IsOptional, IsString } from 'class-validator';

// Sengaja TIDAK mengizinkan update `options` di sini -- mengubah pilihan
// jawaban soal yang sudah pernah dipakai di attempt manapun berisiko
// merusak integritas jawaban historis. Kalau opsinya salah, lebih aman
// bikin question baru daripada edit in-place.
export class UpdateQuestionDto {
  @IsOptional()
  @IsString()
  questionText?: string;

  @IsOptional()
  @IsIn(['EASY', 'MEDIUM', 'HARD'])
  difficulty?: string;

  @IsOptional()
  @IsInt()
  competencyId?: number;
}
