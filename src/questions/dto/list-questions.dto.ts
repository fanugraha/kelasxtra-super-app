import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListQuestionsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  questionBankId?: number;
}
