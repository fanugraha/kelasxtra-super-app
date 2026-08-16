import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsInt, ValidateNested } from 'class-validator';
import { SubmitAssessmentAnswerDto } from './submit-assessment-answer.dto';

export class SubmitAssessmentDto {
  @IsInt()
  attemptId: number;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SubmitAssessmentAnswerDto)
  answers: SubmitAssessmentAnswerDto[];
}
