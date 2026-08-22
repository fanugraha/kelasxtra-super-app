#!/bin/bash
set -e
echo ">> Fix bug NYATA (bukan sekadar test): refresh token hashing pakai bcrypt yang cuma proses 72 byte pertama input -- JWT panjang (apalagi kalau email-nya panjang) sering punya 72 byte pertama IDENTIK antar token berbeda, bikin bcrypt.compare salah anggap token lama yang sudah di-revoke sebagai masih cocok. Diganti SHA-256 (proses seluruh input, deterministik, sekalian jadi lookup O(1) pakai index yang sudah ada, bukan loop O(n))."

mkdir -p "$(dirname "src/auth/auth.service.ts")"
echo ">> Menulis src/auth/auth.service.ts"
cat > src/auth/auth.service.ts << 'KELASXTRA_FIX_REFRESH_HASH_SHA256_22AUG2026'
import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomUUID } from 'crypto';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditLogService } from '../common/services/audit-log.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';

const REFRESH_TOKEN_TTL_DAYS = 7;
const MAX_FAILED_LOGIN_ATTEMPTS = 5;
const LOCKOUT_DURATION_MINUTES = 15;

@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
    private prisma: PrismaService,
    private auditLog: AuditLogService,
  ) {}

  async register(registerDto: RegisterDto) {
    const existingUser = await this.usersService.findUserByEmail(registerDto.email);

    if (existingUser) {
      throw new ConflictException('Email sudah terdaftar.');
    }

    const hashedPassword = await bcrypt.hash(registerDto.password, 10);
    const role = registerDto.role ?? 'STUDENT';

    const newUser =
      role === 'TEACHER'
        ? await this.usersService.createTeacherUser({
            email: registerDto.email,
            hashedPassword,
            name: registerDto.name,
          })
        : await this.usersService.createStudentUser({
            email: registerDto.email,
            hashedPassword,
            name: registerDto.name,
          });

    await this.auditLog.record('REGISTER', newUser.id, { email: newUser.email, role: role });

    return this.issueTokenPair(newUser.id, newUser.email, newUser.role.name);
  }

  async loginWithEmailPassword(loginDto: LoginDto) {
    const existingUser = await this.usersService.findUserByEmail(loginDto.email);

    if (!existingUser) {
      throw new UnauthorizedException('Email atau password salah.');
    }

    // Suspend/deactivate harus efektif dari titik login juga (bukan cuma
    // dicek ulang di JwtStrategy untuk request yang sudah punya token).
    if (existingUser.status !== 'ACTIVE') {
      throw new UnauthorizedException('Akun tidak aktif. Hubungi admin.');
    }

    if (existingUser.lockedUntil && existingUser.lockedUntil > new Date()) {
      throw new UnauthorizedException(
        `Akun terkunci sementara karena terlalu banyak percobaan login gagal. Coba lagi setelah ${existingUser.lockedUntil.toISOString()}.`,
      );
    }

    const isPasswordCorrect = await bcrypt.compare(loginDto.password, existingUser.password);

    if (!isPasswordCorrect) {
      await this.registerFailedLoginAttempt(existingUser.id, existingUser.failedLoginAttempts);
      await this.auditLog.record('LOGIN_FAILED', existingUser.id, { email: existingUser.email });
      throw new UnauthorizedException('Email atau password salah.');
    }

    // Login sukses: reset counter lockout.
    if (existingUser.failedLoginAttempts > 0 || existingUser.lockedUntil) {
      await this.prisma.user.update({
        where: { id: existingUser.id },
        data: { failedLoginAttempts: 0, lockedUntil: null },
      });
    }

    await this.auditLog.record('LOGIN_SUCCESS', existingUser.id, { email: existingUser.email });

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
      return { loggedOut: true };
    }

    const matchingRecord = await this.findMatchingActiveRefreshToken(payload.sub, refreshToken);

    if (matchingRecord) {
      await this.prisma.refreshToken.update({
        where: { id: matchingRecord.id },
        data: { revoked: true },
      });
      await this.auditLog.record('LOGOUT', payload.sub);
    }

    return { loggedOut: true };
  }

  async getCurrentUser(userId: number) {
    const user = await this.usersService.findUserById(userId);

    if (!user) {
      throw new UnauthorizedException('User tidak ditemukan.');
    }

    // password sudah wajib di-strip; failedLoginAttempts/lockedUntil adalah
    // detail internal lockout tracking yang juga tidak boleh bocor ke client.
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { password: _password, failedLoginAttempts: _fla, lockedUntil: _lu, ...safeUser } = user;
    return safeUser;
  }

  private async registerFailedLoginAttempt(userId: number, currentAttempts: number) {
    const nextAttempts = currentAttempts + 1;

    if (nextAttempts >= MAX_FAILED_LOGIN_ATTEMPTS) {
      const lockedUntil = new Date();
      lockedUntil.setMinutes(lockedUntil.getMinutes() + LOCKOUT_DURATION_MINUTES);

      await this.prisma.user.update({
        where: { id: userId },
        data: { failedLoginAttempts: nextAttempts, lockedUntil },
      });

      await this.auditLog.record('ACCOUNT_LOCKED', userId, { untilIso: lockedUntil.toISOString() });
      return;
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: { failedLoginAttempts: nextAttempts },
    });
  }

  // SHA-256, BUKAN bcrypt -- bcrypt cuma memproses 72 byte pertama dari
  // input, dan JWT yang panjang (apalagi kalau email-nya panjang) sering
  // punya 72 byte pertama yang IDENTIK antar token berbeda (header + awal
  // payload sama, bagian yang beda seperti jti/iat/exp ada di belakang).
  // Akibatnya bcrypt.compare bisa menganggap dua refresh token BERBEDA
  // sebagai "cocok" -- ini yang bikin refresh token lama yang sudah
  // di-revoke tetap keterima. SHA-256 memproses seluruh input tanpa
  // truncation, jadi tidak ada masalah ini. Efek sampingnya malah bagus:
  // hash jadi deterministik, bisa langsung findUnique via index (O(1))
  // alih-alih loop bcrypt.compare ke semua candidate (O(n), lambat).
  private hashRefreshToken(rawToken: string): string {
    return createHash('sha256').update(rawToken).digest('hex');
  }

  private async findMatchingActiveRefreshToken(userId: number, rawToken: string) {
    const tokenHash = this.hashRefreshToken(rawToken);

    return this.prisma.refreshToken.findFirst({
      where: {
        userId,
        tokenHash,
        revoked: false,
        expiresAt: { gt: new Date() },
      },
    });
  }

  private async issueTokenPair(userId: number, email: string, roleName: string) {
    // jti acak -- tanpa ini, JWT HS256 deterministik: kalau dua token
    // di-issue di detik (iat) yang sama persis dengan payload identik
    // (mis. register lalu langsung refresh), string token-nya bisa SAMA
    // PERSIS, dan itu merusak jaminan rotation (token "lama" yang harusnya
    // invalid ternyata masih cocok dengan row baru yang belum di-revoke).
    const tokenPayload = { sub: userId, email, role: roleName, jti: randomUUID() };

    const accessToken = await this.jwtService.signAsync(tokenPayload, {
      secret: process.env.JWT_ACCESS_SECRET,
      expiresIn: '15m',
    });

    const refreshToken = await this.jwtService.signAsync(tokenPayload, {
      secret: process.env.JWT_REFRESH_SECRET,
      expiresIn: `${REFRESH_TOKEN_TTL_DAYS}d`,
    });

    const tokenHash = this.hashRefreshToken(refreshToken);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TOKEN_TTL_DAYS);

    await this.prisma.refreshToken.create({
      data: { userId, tokenHash, expiresAt },
    });

    return { accessToken, refreshToken };
  }
}
KELASXTRA_FIX_REFRESH_HASH_SHA256_22AUG2026

echo ""
echo ">> Selesai. Tidak ada perubahan schema -- kolom tokenHash sudah cukup panjang buat hex SHA-256 (64 karakter)."
echo "Langkah selanjutnya:"
echo "1. npm run test:e2e"
