import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString } from 'class-validator';

export class ListCoursesDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  teacherId?: number;

  // Default service hanya kembalikan PUBLISHED untuk non-owner/non-admin --
  // lihat CoursesService.findAll().
  @IsOptional()
  @IsString()
  status?: string;
}
