import { IsIn, IsOptional } from 'class-validator';

export class ListUsersDto {
  @IsOptional()
  @IsIn(['STUDENT', 'TEACHER', 'ADMIN', 'PARENT', 'TUTOR', 'PROFESSIONAL'])
  role?: string;

  @IsOptional()
  @IsIn(['ACTIVE', 'SUSPENDED', 'DEACTIVATED'])
  status?: string;
}
