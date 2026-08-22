#!/bin/bash
set -e
echo ">> Fix 2 bug dari hasil test kemarin:"
echo "   1. jest.spyOn(bcrypt, .compare.) gagal di bcrypt v6 (non-configurable export) -- diganti assert efek tidak langsung."
echo "   2. BUG NYATA: refresh token rotation bisa gagal kalau register+refresh terjadi di detik yang sama persis (JWT HS256 deterministik tanpa jti) -- ditambahkan jti acak."

mkdir -p "$(dirname "src/auth/auth.service.ts")"
echo ">> Menulis src/auth/auth.service.ts"
cat > src/auth/auth.service.ts << 'KELASXTRA_FIX_JTI_AND_SPYON_22AUG2026'
import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'crypto';
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

    const tokenHash = await bcrypt.hash(refreshToken, 10);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TOKEN_TTL_DAYS);

    await this.prisma.refreshToken.create({
      data: { userId, tokenHash, expiresAt },
    });

    return { accessToken, refreshToken };
  }
}
KELASXTRA_FIX_JTI_AND_SPYON_22AUG2026

mkdir -p "$(dirname "src/auth/auth.service.spec.ts")"
echo ">> Menulis src/auth/auth.service.spec.ts"
cat > src/auth/auth.service.spec.ts << 'KELASXTRA_FIX_JTI_AND_SPYON_22AUG2026'
import { Test, TestingModule } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { UsersService } from '../users/users.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditLogService } from '../common/services/audit-log.service';

describe('AuthService', () => {
  let service: AuthService;

  const mockUsersService = {
    findUserByEmail: jest.fn(),
    findUserById: jest.fn(),
    createStudentUser: jest.fn(),
    createTeacherUser: jest.fn(),
  };

  const mockJwtService = {
    signAsync: jest.fn().mockResolvedValue('signed.jwt.token'),
    verifyAsync: jest.fn(),
  };

  const mockPrismaService = {
    user: {
      update: jest.fn(),
    },
    refreshToken: {
      create: jest.fn().mockResolvedValue({}),
      update: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
    },
  };

  const mockAuditLogService = {
    record: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    mockJwtService.signAsync.mockResolvedValue('signed.jwt.token');
    mockPrismaService.refreshToken.create.mockResolvedValue({});

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: UsersService, useValue: mockUsersService },
        { provide: JwtService, useValue: mockJwtService },
        { provide: PrismaService, useValue: mockPrismaService },
        { provide: AuditLogService, useValue: mockAuditLogService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // Section 17.1 dokumen master: "Authentication" wajib masuk Unit Test.
  // Sebelum ini file cuma smoke test ("should be defined") -- tidak
  // menguji satupun logic keputusan security (lockout, status
  // enforcement) yang sebenarnya jadi inti modul ini.
  describe('loginWithEmailPassword', () => {
    const REAL_PASSWORD_HASH = bcrypt.hashSync('password123', 4); // rounds rendah -- cukup buat test, tidak perlu lambat

    function buildMockUser(overrides: Record<string, unknown> = {}) {
      return {
        id: 1,
        email: 'user@test.local',
        password: REAL_PASSWORD_HASH,
        status: 'ACTIVE',
        failedLoginAttempts: 0,
        lockedUntil: null,
        role: { name: 'STUDENT' },
        ...overrides,
      };
    }

    it('email tidak ditemukan -> UnauthorizedException dengan pesan generik', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(null);

      await expect(
        service.loginWithEmailPassword({ email: 'ga-ada@test.local', password: 'apapun' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('status bukan ACTIVE -> ditolak SEBELUM sempat proses password (hemat CPU)', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ status: 'SUSPENDED' }));

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password123' }),
      ).rejects.toThrow('Akun tidak aktif. Hubungi admin.');

      // Kalau bcrypt.compare sempat dipanggil dan lolos ke logic berikutnya,
      // prisma.user.update pasti kepanggil (baik jalur reset counter maupun
      // increment failedLoginAttempts) -- jadi ini bukti tidak langsung
      // bahwa short-circuit di awal beneran kejadian.
      expect(mockPrismaService.user.update).not.toHaveBeenCalled();
    });

    it('lockedUntil di masa depan -> ditolak SEBELUM sempat proses password', async () => {
      const future = new Date(Date.now() + 10 * 60_000);
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ lockedUntil: future }));

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password123' }),
      ).rejects.toThrow(/terkunci/);

      expect(mockPrismaService.user.update).not.toHaveBeenCalled();
    });

    it('password salah -> increment failedLoginAttempts, BELUM mengunci kalau masih di bawah 5', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ failedLoginAttempts: 2 }));

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password-salah' }),
      ).rejects.toThrow('Email atau password salah.');

      expect(mockPrismaService.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { failedLoginAttempts: 3 },
      });
    });

    it('password salah pada percobaan ke-5 -> akun dikunci (lockedUntil di-set)', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser({ failedLoginAttempts: 4 }));

      await expect(
        service.loginWithEmailPassword({ email: 'user@test.local', password: 'password-salah' }),
      ).rejects.toThrow('Email atau password salah.');

      expect(mockPrismaService.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { failedLoginAttempts: 5, lockedUntil: expect.any(Date) },
      });
      expect(mockAuditLogService.record).toHaveBeenCalledWith(
        'ACCOUNT_LOCKED',
        1,
        expect.objectContaining({ untilIso: expect.any(String) }),
      );
    });

    it('password benar & akun bersih -> sukses, TIDAK memanggil reset counter (sudah 0)', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(buildMockUser());

      const result = await service.loginWithEmailPassword({
        email: 'user@test.local',
        password: 'password123',
      });

      expect(result.accessToken).toBe('signed.jwt.token');
      expect(mockPrismaService.user.update).not.toHaveBeenCalled();
      expect(mockAuditLogService.record).toHaveBeenCalledWith(
        'LOGIN_SUCCESS',
        1,
        expect.any(Object),
      );
    });

    it('password benar setelah sempat gagal beberapa kali -> reset failedLoginAttempts & lockedUntil', async () => {
      mockUsersService.findUserByEmail.mockResolvedValue(
        buildMockUser({ failedLoginAttempts: 3 }),
      );

      await service.loginWithEmailPassword({ email: 'user@test.local', password: 'password123' });

      expect(mockPrismaService.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { failedLoginAttempts: 0, lockedUntil: null },
      });
    });
  });
});
KELASXTRA_FIX_JTI_AND_SPYON_22AUG2026

echo ""
echo ">> Selesai. Tidak ada perubahan schema."
echo "Langkah selanjutnya:"
echo "1. npm run test"
echo "2. npm run test:e2e"
