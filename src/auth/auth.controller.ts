import { Body, Controller, Post, Get, HttpCode, HttpStatus, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { CurrentUser } from './decorators/current-user.decorator';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  // Lebih ketat dari limit global (100/menit) — endpoint sensitif yang
  // rawan brute force/spam akun.
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() registerDto: RegisterDto) {
    const tokens = await this.authService.register(registerDto);
    return {
      success: true,
      data: tokens,
      message: 'Registrasi berhasil',
    };
  }

  @Throttle({ default: { limit: 5, ttl: 60_000 } })
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

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  async refresh(@Body() refreshDto: RefreshDto) {
    const tokens = await this.authService.refreshTokens(refreshDto.refreshToken);
    return {
      success: true,
      data: tokens,
      message: 'Token berhasil di-refresh',
    };
  }

  @Post('logout')
  @HttpCode(HttpStatus.OK)
  async logout(@Body() refreshDto: RefreshDto) {
    await this.authService.logout(refreshDto.refreshToken);
    return {
      success: true,
      data: null,
      message: 'Logout berhasil',
    };
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async me(@CurrentUser() currentUser: { userId: number }) {
    const user = await this.authService.getCurrentUser(currentUser.userId);
    return {
      success: true,
      data: user,
      message: 'Success',
    };
  }
}