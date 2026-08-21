import { IsIn, IsInt, IsOptional, IsString } from 'class-validator';

export class CreateMaterialDto {
  @IsInt()
  lessonId!: number;

  @IsString()
  title!: string;

  @IsIn(['VIDEO', 'TEXT', 'PDF', 'LINK'])
  type!: string;

  @IsOptional()
  @IsString()
  content?: string;

  @IsOptional()
  @IsString()
  resourceUrl?: string;
}
