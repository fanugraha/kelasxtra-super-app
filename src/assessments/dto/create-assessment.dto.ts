import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { CreateAssessmentQuestionDto } from './create-assessment-question.dto';

export class CreateAssessmentDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  title!: string;

  @IsOptional()
  @IsIn(['FORMATIVE', 'SUMMATIVE'])
  type?: string;

  @IsOptional()
  @IsInt()
  durationMinutes?: number;

  @IsOptional()
  @IsInt()
  cooldownHours?: number;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateAssessmentQuestionDto)
  questions!: CreateAssessmentQuestionDto[];
}
