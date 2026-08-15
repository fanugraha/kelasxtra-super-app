import { IsDateString, IsIn, IsInt, IsOptional, IsString } from 'class-validator';

export class UpdateGoalDto {
  @IsOptional()
  @IsString()
  goalType?: string;

  @IsOptional()
  @IsString()
  targetValue?: string;

  @IsOptional()
  @IsDateString()
  targetDate?: string;

  @IsOptional()
  @IsInt()
  priority?: number;

  @IsOptional()
  @IsIn(['ACTIVE', 'ACHIEVED', 'CANCELLED'])
  status?: string;
}