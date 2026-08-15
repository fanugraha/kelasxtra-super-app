import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';

const REFRESH_TOKEN_TTL_DAYS = 7;

@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
    private prisma: PrismaService,
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

    return this.issueTokenPair(newUser.id, newUser.email, newUser.role.name);
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

    return this.issueTokenPair(existingUser.id, existingUser.email, existingUser.role.name);
  }

  async refreshTokens(refreshToken: string) {
    let payload: { sub: number; email: string; role: string };

    try {
      payload = await this.jwtService.verifyAsync(refreshToken, {
        secret: process.env.JWT_REFRESH_SECRET,
      });
    } catch {
      throw new UnauthorizedException('Refresh token tidak valid atau sudah kedaluwarsa.');
    }

    const matchingRecord = await this.findMatchingActiveRefreshToken(payload.sub, refreshToken);

    if (!matchingRecord) {
      throw new UnauthorizedException('Refresh token tidak dikenali atau sudah dicabut.');
    }

    // Rotasi: cabut token lama, terbitkan pasangan token baru.
    await this.prisma.refreshToken.update({
      where: { id: matchingRecord.id },
      data: { revoked: true },
    });

    return this.issueTokenPair(payload.sub, payload.email, payload.role);
  }

  async logout(refreshToken: string) {
    let payload: { sub: number };

    try {
      payload = await this.jwtService.verifyAsync(refreshToken, {
        secret: process.env.JWT_REFRESH_SECRET,
      });
    } catch {
      // Token sudah invalid/expired: anggap saja logout berhasil (tidak ada yang perlu dicabut).
      return { loggedOut: true };
    }

    const matchingRecord = await this.findMatchingActiveRefreshToken(payload.sub, refreshToken);

    if (matchingRecord) {
      await this.prisma.refreshToken.update({
        where: { id: matchingRecord.id },
        data: { revoked: true },
      });
    }

    return { loggedOut: true };
  }

  async getCurrentUser(userId: number) {
    const user = await this.usersService.findUserById(userId);

    if (!user) {
      throw new UnauthorizedException('User tidak ditemukan.');
    }

    // Jangan pernah kirim password_hash ke client.
    const { password: _password, ...safeUser } = user;
    return safeUser;
  }

  private async findMatchingActiveRefreshToken(userId: number, rawToken: string) {
    const candidates = await this.prisma.refreshToken.findMany({
      where: {
        userId,
        revoked: false,
        expiresAt: { gt: new Date() },
      },
    });

    for (const candidate of candidates) {
      const isMatch = await bcrypt.compare(rawToken, candidate.tokenHash);
      if (isMatch) {
        return candidate;
      }
    }

    return null;
  }

  private async issueTokenPair(userId: number, email: string, roleName: string) {
    const tokenPayload = { sub: userId, email, role: roleName };

    const accessToken = await this.jwtService.signAsync(tokenPayload, {
      secret: process.env.JWT_ACCESS_SECRET,
      expiresIn: '15m',
    });

    const refreshToken = await this.jwtService.signAsync(tokenPayload, {
      secret: process.env.JWT_REFRESH_SECRET,
      expiresIn: `${REFRESH_TOKEN_TTL_DAYS}d`,
    });

    const tokenHash = await bcrypt.hash(refreshToken, 10);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TOKEN_TTL_DAYS);

    await this.prisma.refreshToken.create({
      data: { userId, tokenHash, expiresAt },
    });

    return { accessToken, refreshToken };
  }
}
