import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListCompetenciesDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  topicId?: number;
}
