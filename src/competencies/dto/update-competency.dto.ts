import { IsInt, IsOptional, IsString } from 'class-validator';

export class UpdateCompetencyDto {
  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsOptional()
  @IsString()
  code?: string;

  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;
}
