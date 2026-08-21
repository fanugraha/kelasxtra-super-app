import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListMaterialsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  lessonId?: number;
}
