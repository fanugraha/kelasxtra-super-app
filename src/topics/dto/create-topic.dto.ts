import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateTopicDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  name!: string;

  @IsOptional()
  @IsInt()
  sequence?: number;
}
