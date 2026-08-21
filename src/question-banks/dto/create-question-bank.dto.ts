import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateQuestionBankDto {
  @IsInt()
  subjectId!: number;

  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsOptional()
  @IsInt()
  competencyId?: number;

  @IsOptional()
  @IsString()
  name?: string;
}
