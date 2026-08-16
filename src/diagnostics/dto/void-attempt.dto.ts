import { IsOptional, IsString, MaxLength } from 'class-validator';

export class VoidAttemptDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}
