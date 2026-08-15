import { Global, Module } from '@nestjs/common';
import { AuditLogService } from './services/audit-log.service';
import { RefreshTokenCleanupService } from './services/refresh-token-cleanup.service';

@Global()
@Module({
  providers: [AuditLogService, RefreshTokenCleanupService],
  exports: [AuditLogService],
})
export class CommonModule {}
