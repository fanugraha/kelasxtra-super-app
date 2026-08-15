import { IsEmail, IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(6)
  @MaxLength(72) // batas byte yang benar-benar dipakai bcrypt; sisanya diam-diam diabaikan
  password!: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsIn(['STUDENT', 'TEACHER'])
  role?: 'STUDENT' | 'TEACHER';
}
