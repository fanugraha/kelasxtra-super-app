import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class CreateQuestionOptionDto {
  @IsString()
  optionText!: string;

  @IsBoolean()
  isCorrect!: boolean;

  @IsOptional()
  sequence?: number;
}
