import { Body, Controller, Post, HttpCode, HttpStatus } from '@nestjs/common';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() registerDto: RegisterDto) {
    const tokens = await this.authService.registerNewStudent(registerDto);
    return {
      success: true,
      data: tokens,
      message: 'Registrasi berhasil',
    };
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(@Body() loginDto: LoginDto) {
    const tokens = await this.authService.loginWithEmailPassword(loginDto);
    return {
      success: true,
      data: tokens,
      message: 'Login berhasil',
    };
  }
}