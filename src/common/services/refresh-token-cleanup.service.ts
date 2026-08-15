import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';

const RETENTION_DAYS_AFTER_REVOKED = 30;

/**
 * Tabel refresh_tokens terus bertambah karena setiap refresh membuat row
 * baru (yang lama cuma di-revoke, bukan dihapus). Job ini membersihkan
 * row yang sudah expired ATAU sudah revoked lebih dari 30 hari, supaya
 * tabel tidak tumbuh tanpa batas.
 */
@Injectable()
export class RefreshTokenCleanupService {
  private readonly logger = new Logger(RefreshTokenCleanupService.name);

  constructor(private prisma: PrismaService) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async cleanupExpiredTokens() {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - RETENTION_DAYS_AFTER_REVOKED);

    const result = await this.prisma.refreshToken.deleteMany({
      where: {
        OR: [{ expiresAt: { lt: new Date() } }, { revoked: true, createdAt: { lt: cutoff } }],
      },
    });

    this.logger.log(`Refresh token cleanup: ${result.count} row dihapus.`);
    return result.count;
  }
}
