import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListLessonsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  courseId?: number;
}
