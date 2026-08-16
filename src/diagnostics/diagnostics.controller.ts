import { Body, Controller, Param, ParseIntPipe, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { DiagnosticsService } from './diagnostics.service';
import { SubmitDiagnosticDto } from './dto/submit-diagnostic.dto';

@Controller('diagnostics')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class DiagnosticsController {
  constructor(private diagnosticsService: DiagnosticsService) {}

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
}
