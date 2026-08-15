import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListTopicsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;
}
