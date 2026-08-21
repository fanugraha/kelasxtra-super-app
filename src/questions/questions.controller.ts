import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { QuestionsService } from './questions.service';
import { CreateQuestionDto } from './dto/create-question.dto';
import { UpdateQuestionDto } from './dto/update-question.dto';
import { ListQuestionsDto } from './dto/list-questions.dto';

@Controller('questions')
@UseGuards(JwtAuthGuard, RolesGuard)
export class QuestionsController {
  constructor(private questionsService: QuestionsService) {}

  // Baca soal (termasuk isCorrect) hanya untuk TEACHER/ADMIN -- kalau
  // STUDENT bisa baca ini, jawaban benar diagnostic/assessment bocor
  // mentah-mentah lewat endpoint ini, di luar jalur submit yang aman.
  @Get()
  @Roles('ADMIN', 'TEACHER')
  async findAll(@Query() query: ListQuestionsDto) {
    const questions = await this.questionsService.findAll(query);
    return { success: true, data: questions, message: 'Success' };
  }

  @Get(':id')
  @Roles('ADMIN', 'TEACHER')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const question = await this.questionsService.findOne(id);
    return { success: true, data: question, message: 'Success' };
  }

  @Post()
  @Roles('ADMIN', 'TEACHER')
  async create(
    @CurrentUser() user: { userId: number; role: string },
    @Body() dto: CreateQuestionDto,
  ) {
    const question = await this.questionsService.create(user, dto);
    return { success: true, data: question, message: 'Question berhasil dibuat' };
  }

  @Put(':id')
  @Roles('ADMIN', 'TEACHER')
  async update(
    @CurrentUser() user: { userId: number; role: string },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateQuestionDto,
  ) {
    const question = await this.questionsService.update(user, id, dto);
    return { success: true, data: question, message: 'Question berhasil diperbarui' };
  }
}
