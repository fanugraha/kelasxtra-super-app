import { IsDateString, IsInt, IsOptional, IsString } from 'class-validator';

export class CreateGoalDto {
  @IsString()
  goalType!: string;

  @IsOptional()
  @IsString()
  targetValue?: string;

  @IsOptional()
  @IsDateString()
  targetDate?: string;

  @IsOptional()
  @IsInt()
  priority?: number;
}