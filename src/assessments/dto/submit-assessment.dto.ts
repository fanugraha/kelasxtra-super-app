import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  ValidateNested,
} from 'class-validator';
import { SubmitAssessmentAnswerDto } from './submit-assessment-answer.dto';

export class SubmitAssessmentDto {
  @IsInt()
  attemptId: number;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => SubmitAssessmentAnswerDto)
  answers: SubmitAssessmentAnswerDto[];
}
