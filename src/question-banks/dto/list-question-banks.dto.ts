import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListQuestionBanksDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  topicId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  competencyId?: number;
}
