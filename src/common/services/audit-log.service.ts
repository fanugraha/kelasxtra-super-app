import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export type AuditAction =
  | 'REGISTER'
  | 'LOGIN_SUCCESS'
  | 'LOGIN_FAILED'
  | 'ACCOUNT_LOCKED'
  | 'LOGOUT'
  | 'USER_STATUS_CHANGED';

/**
 * Mencatat aktivitas keamanan penting (section 15 dokumen: "Audit aktivitas
 * penting seperti login, perubahan role, dan perubahan data akademik").
 * Sengaja tidak pernah throw ke pemanggil — kegagalan audit log tidak boleh
 * menggagalkan flow auth yang sebenarnya.
 */
@Injectable()
export class AuditLogService {
  private readonly logger = new Logger(AuditLogService.name);

  constructor(private prisma: PrismaService) {}

  async record(action: AuditAction, userId: number | null, metadata?: Record<string, unknown>) {
    try {
      await this.prisma.auditLog.create({
        data: {
          userId: userId ?? undefined,
          action,
          metadata: metadata ? JSON.stringify(metadata) : undefined,
        },
      });
    } catch (error) {
      this.logger.error(`Gagal menyimpan audit log (${action})`, error as Error);
    }
  }
}
