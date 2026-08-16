import { IsInt, IsOptional, Min } from 'class-validator';

export class SubmitAssessmentAnswerDto {
  @IsInt()
  questionId: number;

  // null / tidak dikirim berarti soal ini tidak dijawab -> dianggap salah
  @IsOptional()
  @IsInt()
  selectedOptionId?: number | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  timeSpentSeconds?: number;
}
