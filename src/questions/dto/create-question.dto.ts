import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { CreateQuestionOptionDto } from './create-question-option.dto';

export class CreateQuestionDto {
  @IsInt()
  questionBankId!: number;

  @IsOptional()
  @IsInt()
  competencyId?: number;

  @IsString()
  questionText!: string;

  @IsOptional()
  @IsIn(['MULTIPLE_CHOICE', 'TRUE_FALSE', 'ESSAY'])
  questionType?: string;

  @IsOptional()
  @IsIn(['EASY', 'MEDIUM', 'HARD'])
  difficulty?: string;

  // Wajib untuk MULTIPLE_CHOICE/TRUE_FALSE (divalidasi di service, karena
  // aturannya beda per questionType -- ESSAY memang boleh tanpa option).
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => CreateQuestionOptionDto)
  options?: CreateQuestionOptionDto[];
}
