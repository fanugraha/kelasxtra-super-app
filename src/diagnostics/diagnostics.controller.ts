import { Body, Controller, Param, ParseIntPipe, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { DiagnosticsService } from './diagnostics.service';
import { SubmitDiagnosticDto } from './dto/submit-diagnostic.dto';
import { VoidAttemptDto } from './dto/void-attempt.dto';
import { CreateDiagnosticTestDto } from './dto/create-diagnostic-test.dto';

@Controller('diagnostics')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class DiagnosticsController {
  constructor(private diagnosticsService: DiagnosticsService) {}

  // Gap Phase 4: sebelumnya tidak ada cara sama sekali bikin diagnostic
  // test baru selain seed manual. ADMIN-only -- lihat komentar service.
  @Post()
  @Roles('ADMIN')
  async create(@Body() dto: CreateDiagnosticTestDto) {
    const test = await this.diagnosticsService.createTest(dto);
    return { success: true, data: test, message: 'Diagnostic test berhasil dibuat' };
  }

  @Post(':id/start')
  async start(@CurrentUser() user: { userId: number }, @Param('id', ParseIntPipe) id: number) {
    const attempt = await this.diagnosticsService.startAttempt(user.userId, id);
    return { success: true, data: attempt, message: 'Attempt dimulai' };
  }

  @Post(':id/submit')
  async submit(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: SubmitDiagnosticDto,
  ) {
    const result = await this.diagnosticsService.submit(user.userId, id, dto);
    return { success: true, data: result, message: 'Diagnostic berhasil disubmit' };
  }

  // Reset path untuk cap 1x attempt (keputusan bisnis 16 Agustus 2026,
  // item #4) -- @Roles method-level ini override @Roles('STUDENT') di
  // level class, jadi HANYA ADMIN/TEACHER yang bisa panggil endpoint ini.
  @Post('attempts/:attemptId/void')
  @Roles('ADMIN', 'TEACHER')
  async voidAttempt(
    @CurrentUser() user: { userId: number },
    @Param('attemptId', ParseIntPipe) attemptId: number,
    @Body() dto: VoidAttemptDto,
  ) {
    const attempt = await this.diagnosticsService.voidAttempt(user.userId, attemptId, dto.reason);
    return {
      success: true,
      data: attempt,
      message: 'Attempt berhasil di-void, siswa sekarang bisa mengulang diagnostic test ini.',
    };
  }
}
