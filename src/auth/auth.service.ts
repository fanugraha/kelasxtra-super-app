import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';

@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
  ) {}

  async registerNewStudent(registerDto: RegisterDto) {
    const existingUser = await this.usersService.findUserByEmail(registerDto.email);

    if (existingUser) {
      throw new ConflictException('Email sudah terdaftar.');
    }

    const hashedPassword = await bcrypt.hash(registerDto.password, 10);

    const newUser = await this.usersService.createStudentUser({
      email: registerDto.email,
      hashedPassword,
      name: registerDto.name,
    });

    return this.generateTokensForUser(newUser.id, newUser.email, newUser.role.name);
  }

  async loginWithEmailPassword(loginDto: LoginDto) {
    const existingUser = await this.usersService.findUserByEmail(loginDto.email);

    if (!existingUser) {
      throw new UnauthorizedException('Email atau password salah.');
    }

    const isPasswordCorrect = await bcrypt.compare(loginDto.password, existingUser.password);

    if (!isPasswordCorrect) {
      throw new UnauthorizedException('Email atau password salah.');
    }

    return this.generateTokensForUser(existingUser.id, existingUser.email, existingUser.role.name);
  }

  private async generateTokensForUser(userId: number, email: string, roleName: string) {
    const tokenPayload = { sub: userId, email, role: roleName };

    const accessToken = await this.jwtService.signAsync(tokenPayload, {
      secret: process.env.JWT_ACCESS_SECRET,
      expiresIn: '15m',
    });

    const refreshToken = await this.jwtService.signAsync(tokenPayload, {
      secret: process.env.JWT_REFRESH_SECRET,
      expiresIn: '7d',
    });

    return { accessToken, refreshToken };
  }
}