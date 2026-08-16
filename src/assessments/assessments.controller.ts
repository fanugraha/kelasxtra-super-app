import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AssessmentsService } from './assessments.service';
import { SubmitAssessmentDto } from './dto/submit-assessment.dto';

@Controller('assessments')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class AssessmentsController {
  constructor(private assessmentsService: AssessmentsService) {}

  @Post(':id/start')
  async start(@CurrentUser() user: { userId: number }, @Param('id', ParseIntPipe) id: number) {
    const attempt = await this.assessmentsService.startAttempt(user.userId, id);
    return { success: true, data: attempt, message: 'Attempt dimulai' };
  }

  @Post(':id/submit')
  async submit(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: SubmitAssessmentDto,
  ) {
    const result = await this.assessmentsService.submit(user.userId, id, dto);
    return { success: true, data: result, message: 'Assessment berhasil disubmit' };
  }

  // Fix #9: sesuai dokumen master section 12.6, tapi belum pernah ada
  // implementasinya sebelum ini. Tanpa ?attemptId -> hasil attempt
  // SUBMITTED paling baru. Dengan ?attemptId -> lihat attempt spesifik
  // (assessment boleh diulang, jadi bisa ada beberapa hasil di riwayat).
  @Get(':id/results')
  async results(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Query('attemptId') attemptIdRaw?: string,
  ) {
    const attemptId = attemptIdRaw ? Number(attemptIdRaw) : undefined;
    const result = await this.assessmentsService.getResults(user.userId, id, attemptId);
    return { success: true, data: result, message: 'Hasil assessment' };
  }
}
