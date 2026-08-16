import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  ValidateNested,
} from 'class-validator';
import { SubmitAnswerDto } from './submit-answer.dto';

export class SubmitDiagnosticDto {
  @IsInt()
  attemptId: number;

  @IsArray()
  @ArrayMinSize(1)
  // Batas atas kasar -- tidak ada diagnostic test realistis yang butuh
  // >200 soal dalam satu attempt. Ini murni hardening terhadap payload
  // raksasa (temuan QA audit 16 Agustus 2026, item LOW), bukan batas bisnis.
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => SubmitAnswerDto)
  answers: SubmitAnswerDto[];
}
