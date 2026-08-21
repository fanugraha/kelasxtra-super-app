import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditLogService } from '../common/services/audit-log.service';
import { ListUsersDto } from './dto/list-users.dto';
import { UpdateUserStatusDto } from './dto/update-user-status.dto';

// Field yang tidak pernah dikirim ke client -- password (hash) dan
// counter lockout internal (failedLoginAttempts/lockedUntil), sama
// seperti yang sudah diterapkan di AuthService.getCurrentUser().
const SAFE_USER_SELECT = {
  id: true,
  email: true,
  status: true,
  createdAt: true,
  updatedAt: true,
  role: { select: { id: true, name: true } },
  studentProfile: { select: { id: true, studentCode: true, gradeLevel: true } },
  teacherProfile: { select: { id: true, teacherCode: true, name: true, verificationStatus: true } },
} as const;

@Injectable()
export class AdminService {
  constructor(
    private prisma: PrismaService,
    private auditLog: AuditLogService,
  ) {}

  async findAll(query: ListUsersDto) {
    return this.prisma.user.findMany({
      where: {
        status: query.status,
        role: query.role ? { name: query.role } : undefined,
      },
      select: SAFE_USER_SELECT,
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: number) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: SAFE_USER_SELECT,
    });

    if (!user) {
      throw new NotFoundException('User tidak ditemukan.');
    }

    return user;
  }

  // Melengkapi enforcement status yang sudah dibangun di AuthService.login()
  // dan JwtStrategy.validate() -- sebelum endpoint ini ada, kolom `status`
  // cuma hiasan di database, tidak ada cara mengubahnya lewat aplikasi.
  async updateStatus(actorUserId: number, targetUserId: number, dto: UpdateUserStatusDto) {
    if (actorUserId === targetUserId) {
      throw new BadRequestException('Tidak bisa mengubah status akun sendiri.');
    }

    const target = await this.prisma.user.findUnique({ where: { id: targetUserId } });
    if (!target) {
      throw new NotFoundException('User tidak ditemukan.');
    }

    const updated = await this.prisma.user.update({
      where: { id: targetUserId },
      data: { status: dto.status },
      select: SAFE_USER_SELECT,
    });

    await this.auditLog.record('USER_STATUS_CHANGED', actorUserId, {
      targetUserId,
      from: target.status,
      to: dto.status,
    });

    return updated;
  }
}
