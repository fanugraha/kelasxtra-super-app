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
import { QuestionBanksService } from './question-banks.service';
import { CreateQuestionBankDto } from './dto/create-question-bank.dto';
import { ListQuestionBanksDto } from './dto/list-question-banks.dto';

@Controller('question-banks')
@UseGuards(JwtAuthGuard, RolesGuard)
export class QuestionBanksController {
  constructor(private questionBanksService: QuestionBanksService) {}

  // Semua role yang login boleh baca (TEACHER perlu lihat bank orang lain
  // juga untuk referensi, STUDENT tidak pernah panggil ini langsung dari
  // UI tapi tidak ada alasan untuk disembunyikan -- isinya bukan data pribadi).
  @Get()
  async findAll(@Query() query: ListQuestionBanksDto) {
    const banks = await this.questionBanksService.findAll(query);
    return { success: true, data: banks, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const bank = await this.questionBanksService.findOne(id);
    return { success: true, data: bank, message: 'Success' };
  }

  @Post()
  @Roles('ADMIN', 'TEACHER')
  async create(
    @CurrentUser() user: { userId: number; role: string },
    @Body() dto: CreateQuestionBankDto,
  ) {
    const bank = await this.questionBanksService.create(user, dto);
    return { success: true, data: bank, message: 'Question bank berhasil dibuat' };
  }
}
