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
