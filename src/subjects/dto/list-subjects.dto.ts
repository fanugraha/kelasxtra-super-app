import { IsIn, IsOptional, IsString } from 'class-validator';

export class ListSubjectsDto {
  // Default-nya cuma subject ACTIVE yang tampil (dipakai student/teacher).
  // Admin bisa kirim includeInactive=true untuk lihat semua termasuk yang INACTIVE.
  @IsOptional()
  @IsIn(['true', 'false'])
  includeInactive?: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;
}
