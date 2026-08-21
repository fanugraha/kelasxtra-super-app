import { IsInt, IsString } from 'class-validator';

export class CreateCourseDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  title!: string;
}
