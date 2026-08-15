import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateCompetencyDto {
  @IsInt()
  subjectId!: number;

  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsString()
  code!: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;
}
