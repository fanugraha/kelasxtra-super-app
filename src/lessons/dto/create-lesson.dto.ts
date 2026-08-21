import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateLessonDto {
  @IsInt()
  courseId!: number;

  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsString()
  title!: string;

  @IsOptional()
  @IsInt()
  sequence?: number;
}
