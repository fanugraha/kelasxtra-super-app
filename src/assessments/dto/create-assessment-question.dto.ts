import { IsInt, IsOptional, IsNumber, Min } from 'class-validator';

export class CreateAssessmentQuestionDto {
  @IsInt()
  questionId!: number;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  points?: number;
}
