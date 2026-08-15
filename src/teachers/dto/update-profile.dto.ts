import { IsInt, IsOptional, IsString } from 'class-validator';

export class UpdateTeacherProfileDto {
  @IsOptional()
  @IsString()
  bio?: string;

  @IsOptional()
  @IsString()
  education?: string;

  @IsOptional()
  @IsInt()
  experienceYears?: number;
}
