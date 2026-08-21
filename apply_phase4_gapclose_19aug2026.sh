#!/bin/bash
set -e
echo ">> Menutup gap Phase 4: Content (Course/Lesson/Material), Question Bank + Questions, sisi-baca (competencies/learning-path/progress), Admin user management, dan endpoint create Diagnostic Test + Assessment yang sebelumnya tidak ada sama sekali."
echo ">> Termasuk hotfix diagnostics.service.ts (cap 1x/void/duration-flag yang sempat hilang) + audit-log.service.ts (action baru USER_STATUS_CHANGED)."

mkdir -p "$(dirname "src/students/students.service.ts")"
echo ">> Menulis src/students/students.service.ts"
cat > src/students/students.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { CreateGoalDto } from './dto/create-goal.dto';
import { UpdateGoalDto } from './dto/update-goal.dto';

@Injectable()
export class StudentsService {
  constructor(private prisma: PrismaService) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({
      where: { userId },
    });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  async getMyProfile(userId: number) {
    return this.findProfileByUserId(userId);
  }

  async updateMyProfile(userId: number, dto: UpdateProfileDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.studentProfile.update({
      where: { id: profile.id },
      data: dto,
    });
  }

  async getMyGoals(userId: number) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.studentGoal.findMany({
      where: { studentId: profile.id },
      orderBy: { priority: 'desc' },
    });
  }

  async createGoal(userId: number, dto: CreateGoalDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.studentGoal.create({
      data: {
        studentId: profile.id,
        goalType: dto.goalType,
        targetValue: dto.targetValue,
        targetDate: dto.targetDate ? new Date(dto.targetDate) : undefined,
        priority: dto.priority ?? 0,
      },
    });
  }

  async updateGoal(userId: number, goalId: number, dto: UpdateGoalDto) {
    const profile = await this.findProfileByUserId(userId);

    const goal = await this.prisma.studentGoal.findUnique({
      where: { id: goalId },
    });

    if (!goal) {
      throw new NotFoundException('Goal tidak ditemukan.');
    }

    // Pastikan goal ini benar-benar milik student yang sedang login.
    if (goal.studentId !== profile.id) {
      throw new ForbiddenException('Kamu tidak punya akses ke goal ini.');
    }

    return this.prisma.studentGoal.update({
      where: { id: goalId },
      data: {
        ...dto,
        targetDate: dto.targetDate ? new Date(dto.targetDate) : undefined,
      },
    });
  }

  // Gap Phase 4 (19 Agustus 2026): mesin Learning Engine sudah nulis
  // StudentCompetency/LearningPath/StudentProgress tiap kali submit, tapi
  // sebelum ini TIDAK ADA satu pun endpoint buat siswa lihat hasilnya --
  // section 12.3 dokumen master eksplisit minta 3 endpoint ini.

  async getMyCompetencies(userId: number) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.studentCompetency.findMany({
      where: { studentId: profile.id },
      include: {
        competency: { include: { subject: true, topic: true } },
      },
      orderBy: { updatedAt: 'desc' },
    });
  }

  // Cuma path yang ACTIVE -- path lama yang sudah ARCHIVED/COMPLETED bukan
  // "learning path saat ini". LearningPathReconciler juga cuma pernah
  // menyentuh path ber-status ACTIVE (lihat getOrCreateActivePath).
  async getMyLearningPath(userId: number) {
    const profile = await this.findProfileByUserId(userId);

    const path = await this.prisma.learningPath.findFirst({
      where: { studentId: profile.id, status: 'ACTIVE' },
      orderBy: { generatedAt: 'desc' },
      include: {
        items: {
          orderBy: { sequence: 'asc' },
          include: {
            competency: true,
            lesson: { include: { course: true } },
          },
        },
      },
    });

    if (!path) {
      throw new NotFoundException(
        'Belum ada learning path -- biasanya baru terbentuk setelah ada competency yang butuh perhatian dari diagnostic/assessment.',
      );
    }

    return path;
  }

  async getMyProgress(userId: number) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.studentProgress.findMany({
      where: { studentId: profile.id },
      include: {
        lesson: { include: { course: true } },
      },
      orderBy: { updatedAt: 'desc' },
    });
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/students/students.controller.ts")"
echo ">> Menulis src/students/students.controller.ts"
cat > src/students/students.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { StudentsService } from './students.service';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { CreateGoalDto } from './dto/create-goal.dto';
import { UpdateGoalDto } from './dto/update-goal.dto';

@Controller('students')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class StudentsController {
  constructor(private studentsService: StudentsService) {}

  @Get('me')
  async getMyProfile(@CurrentUser() user: { userId: number }) {
    const profile = await this.studentsService.getMyProfile(user.userId);
    return { success: true, data: profile, message: 'Success' };
  }

  @Put('me')
  async updateMyProfile(
    @CurrentUser() user: { userId: number },
    @Body() dto: UpdateProfileDto,
  ) {
    const profile = await this.studentsService.updateMyProfile(user.userId, dto);
    return { success: true, data: profile, message: 'Profil berhasil diperbarui' };
  }

  @Get('me/goals')
  async getMyGoals(@CurrentUser() user: { userId: number }) {
    const goals = await this.studentsService.getMyGoals(user.userId);
    return { success: true, data: goals, message: 'Success' };
  }

  @Post('me/goals')
  async createGoal(
    @CurrentUser() user: { userId: number },
    @Body() dto: CreateGoalDto,
  ) {
    const goal = await this.studentsService.createGoal(user.userId, dto);
    return { success: true, data: goal, message: 'Goal berhasil dibuat' };
  }

  @Put('me/goals/:id')
  async updateGoal(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateGoalDto,
  ) {
    const goal = await this.studentsService.updateGoal(user.userId, id, dto);
    return { success: true, data: goal, message: 'Goal berhasil diperbarui' };
  }

  @Get('me/competencies')
  async getMyCompetencies(@CurrentUser() user: { userId: number }) {
    const competencies = await this.studentsService.getMyCompetencies(user.userId);
    return { success: true, data: competencies, message: 'Success' };
  }

  @Get('me/learning-path')
  async getMyLearningPath(@CurrentUser() user: { userId: number }) {
    const path = await this.studentsService.getMyLearningPath(user.userId);
    return { success: true, data: path, message: 'Success' };
  }

  @Get('me/progress')
  async getMyProgress(@CurrentUser() user: { userId: number }) {
    const progress = await this.studentsService.getMyProgress(user.userId);
    return { success: true, data: progress, message: 'Success' };
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/question-banks/question-banks.module.ts")"
echo ">> Menulis src/question-banks/question-banks.module.ts"
cat > src/question-banks/question-banks.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { QuestionBanksController } from './question-banks.controller';
import { QuestionBanksService } from './question-banks.service';

@Module({
  controllers: [QuestionBanksController],
  providers: [QuestionBanksService],
  exports: [QuestionBanksService],
})
export class QuestionBanksModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/question-banks/question-banks.controller.ts")"
echo ">> Menulis src/question-banks/question-banks.controller.ts"
cat > src/question-banks/question-banks.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/question-banks/question-banks.service.ts")"
echo ">> Menulis src/question-banks/question-banks.service.ts"
cat > src/question-banks/question-banks.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateQuestionBankDto } from './dto/create-question-bank.dto';
import { ListQuestionBanksDto } from './dto/list-question-banks.dto';

@Injectable()
export class QuestionBanksService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListQuestionBanksDto) {
    return this.prisma.questionBank.findMany({
      where: {
        subjectId: query.subjectId,
        topicId: query.topicId,
        competencyId: query.competencyId,
      },
      include: { _count: { select: { questions: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: number) {
    const bank = await this.prisma.questionBank.findUnique({
      where: { id },
      include: {
        questions: {
          include: { options: { orderBy: { sequence: 'asc' } } },
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    if (!bank) {
      throw new NotFoundException('Question bank tidak ditemukan.');
    }

    return bank;
  }

  // ADMIN bisa bikin bank platform-wide (teacherId null). TEACHER hanya
  // bisa bikin bank miliknya sendiri -- ownership ini yang jadi dasar
  // pengecekan di QuestionsService.create() nanti (soal cuma boleh
  // ditambahkan oleh pemilik bank atau ADMIN).
  async create(
    actor: { userId: number; role: string },
    dto: CreateQuestionBankDto,
  ) {
    await this.ensureSubjectExists(dto.subjectId);

    let teacherId: number | undefined;
    if (actor.role === 'TEACHER') {
      const profile = await this.prisma.teacherProfile.findUnique({
        where: { userId: actor.userId },
      });
      if (!profile) {
        throw new NotFoundException('Profil teacher tidak ditemukan.');
      }
      teacherId = profile.id;
    }

    return this.prisma.questionBank.create({
      data: {
        subjectId: dto.subjectId,
        topicId: dto.topicId,
        competencyId: dto.competencyId,
        teacherId,
        name: dto.name,
      },
    });
  }

  private async ensureSubjectExists(subjectId: number) {
    const subject = await this.prisma.subject.findUnique({ where: { id: subjectId } });
    if (!subject) {
      throw new NotFoundException('Subject untuk question bank ini tidak ditemukan.');
    }
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/question-banks/dto/create-question-bank.dto.ts")"
echo ">> Menulis src/question-banks/dto/create-question-bank.dto.ts"
cat > src/question-banks/dto/create-question-bank.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateQuestionBankDto {
  @IsInt()
  subjectId!: number;

  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsOptional()
  @IsInt()
  competencyId?: number;

  @IsOptional()
  @IsString()
  name?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/question-banks/dto/list-question-banks.dto.ts")"
echo ">> Menulis src/question-banks/dto/list-question-banks.dto.ts"
cat > src/question-banks/dto/list-question-banks.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListQuestionBanksDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  topicId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  competencyId?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/questions.module.ts")"
echo ">> Menulis src/questions/questions.module.ts"
cat > src/questions/questions.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { QuestionsController } from './questions.controller';
import { QuestionsService } from './questions.service';

@Module({
  controllers: [QuestionsController],
  providers: [QuestionsService],
  exports: [QuestionsService],
})
export class QuestionsModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/questions.controller.ts")"
echo ">> Menulis src/questions/questions.controller.ts"
cat > src/questions/questions.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/questions.service.ts")"
echo ">> Menulis src/questions/questions.service.ts"
cat > src/questions/questions.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateQuestionDto } from './dto/create-question.dto';
import { UpdateQuestionDto } from './dto/update-question.dto';
import { ListQuestionsDto } from './dto/list-questions.dto';

@Injectable()
export class QuestionsService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListQuestionsDto) {
    return this.prisma.question.findMany({
      where: { questionBankId: query.questionBankId },
      include: { options: { orderBy: { sequence: 'asc' } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: number) {
    const question = await this.prisma.question.findUnique({
      where: { id },
      include: { options: { orderBy: { sequence: 'asc' } } },
    });

    if (!question) {
      throw new NotFoundException('Question tidak ditemukan.');
    }

    return question;
  }

  async create(actor: { userId: number; role: string }, dto: CreateQuestionDto) {
    const bank = await this.prisma.questionBank.findUnique({
      where: { id: dto.questionBankId },
    });
    if (!bank) {
      throw new NotFoundException('Question bank tidak ditemukan.');
    }

    await this.ensureCanEditBank(actor, bank);

    const questionType = dto.questionType ?? 'MULTIPLE_CHOICE';
    this.validateOptions(questionType, dto.options);

    return this.prisma.question.create({
      data: {
        questionBankId: dto.questionBankId,
        competencyId: dto.competencyId,
        questionText: dto.questionText,
        questionType,
        difficulty: dto.difficulty ?? 'MEDIUM',
        options: dto.options
          ? {
              create: dto.options.map((o, index) => ({
                optionText: o.optionText,
                isCorrect: o.isCorrect,
                sequence: o.sequence ?? index,
              })),
            }
          : undefined,
      },
      include: { options: { orderBy: { sequence: 'asc' } } },
    });
  }

  async update(actor: { userId: number; role: string }, id: number, dto: UpdateQuestionDto) {
    const question = await this.prisma.question.findUnique({
      where: { id },
      include: { questionBank: true },
    });
    if (!question) {
      throw new NotFoundException('Question tidak ditemukan.');
    }

    await this.ensureCanEditBank(actor, question.questionBank);

    return this.prisma.question.update({
      where: { id },
      data: dto,
      include: { options: { orderBy: { sequence: 'asc' } } },
    });
  }

  // Bank tanpa teacherId (null) = bank platform-wide -- hanya ADMIN yang
  // boleh menambah/mengubah soal di dalamnya. Bank dengan teacherId
  // terisi = milik teacher itu -- hanya teacher pemiliknya atau ADMIN.
  private async ensureCanEditBank(
    actor: { userId: number; role: string },
    bank: { teacherId: number | null },
  ) {
    if (actor.role === 'ADMIN') {
      return;
    }

    if (bank.teacherId === null) {
      throw new ForbiddenException('Question bank ini milik platform, hanya ADMIN yang bisa mengelola soalnya.');
    }

    const profile = await this.prisma.teacherProfile.findUnique({
      where: { userId: actor.userId },
    });
    if (!profile || profile.id !== bank.teacherId) {
      throw new ForbiddenException('Kamu bukan pemilik question bank ini.');
    }
  }

  // MULTIPLE_CHOICE/TRUE_FALSE wajib punya opsi dengan TEPAT SATU yang
  // benar -- kalau nol atau lebih dari satu, soal ini tidak bisa dinilai
  // dengan benar oleh EvidenceAggregator (lihat fix Bug #1 di sana).
  // ESSAY sengaja dikecualikan -- tidak dinilai otomatis lewat option.
  private validateOptions(
    questionType: string,
    options: CreateQuestionDto['options'],
  ) {
    if (questionType === 'ESSAY') {
      return;
    }

    if (!options || options.length < 2) {
      throw new BadRequestException(
        `Soal tipe ${questionType} butuh minimal 2 pilihan jawaban.`,
      );
    }

    const correctCount = options.filter((o) => o.isCorrect).length;
    if (correctCount !== 1) {
      throw new BadRequestException(
        `Soal tipe ${questionType} harus punya TEPAT SATU pilihan jawaban yang benar (sekarang: ${correctCount}).`,
      );
    }
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/dto/create-question.dto.ts")"
echo ">> Menulis src/questions/dto/create-question.dto.ts"
cat > src/questions/dto/create-question.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { CreateQuestionOptionDto } from './create-question-option.dto';

export class CreateQuestionDto {
  @IsInt()
  questionBankId!: number;

  @IsOptional()
  @IsInt()
  competencyId?: number;

  @IsString()
  questionText!: string;

  @IsOptional()
  @IsIn(['MULTIPLE_CHOICE', 'TRUE_FALSE', 'ESSAY'])
  questionType?: string;

  @IsOptional()
  @IsIn(['EASY', 'MEDIUM', 'HARD'])
  difficulty?: string;

  // Wajib untuk MULTIPLE_CHOICE/TRUE_FALSE (divalidasi di service, karena
  // aturannya beda per questionType -- ESSAY memang boleh tanpa option).
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => CreateQuestionOptionDto)
  options?: CreateQuestionOptionDto[];
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/dto/create-question-option.dto.ts")"
echo ">> Menulis src/questions/dto/create-question-option.dto.ts"
cat > src/questions/dto/create-question-option.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class CreateQuestionOptionDto {
  @IsString()
  optionText!: string;

  @IsBoolean()
  isCorrect!: boolean;

  @IsOptional()
  sequence?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/dto/update-question.dto.ts")"
echo ">> Menulis src/questions/dto/update-question.dto.ts"
cat > src/questions/dto/update-question.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn, IsInt, IsOptional, IsString } from 'class-validator';

// Sengaja TIDAK mengizinkan update `options` di sini -- mengubah pilihan
// jawaban soal yang sudah pernah dipakai di attempt manapun berisiko
// merusak integritas jawaban historis. Kalau opsinya salah, lebih aman
// bikin question baru daripada edit in-place.
export class UpdateQuestionDto {
  @IsOptional()
  @IsString()
  questionText?: string;

  @IsOptional()
  @IsIn(['EASY', 'MEDIUM', 'HARD'])
  difficulty?: string;

  @IsOptional()
  @IsInt()
  competencyId?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/questions/dto/list-questions.dto.ts")"
echo ">> Menulis src/questions/dto/list-questions.dto.ts"
cat > src/questions/dto/list-questions.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListQuestionsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  questionBankId?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/courses/courses.module.ts")"
echo ">> Menulis src/courses/courses.module.ts"
cat > src/courses/courses.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { CoursesController } from './courses.controller';
import { CoursesService } from './courses.service';

@Module({
  controllers: [CoursesController],
  providers: [CoursesService],
  exports: [CoursesService],
})
export class CoursesModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/courses/courses.controller.ts")"
echo ">> Menulis src/courses/courses.controller.ts"
cat > src/courses/courses.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
import { CoursesService } from './courses.service';
import { CreateCourseDto } from './dto/create-course.dto';
import { UpdateCourseDto } from './dto/update-course.dto';
import { ListCoursesDto } from './dto/list-courses.dto';

@Controller('courses')
@UseGuards(JwtAuthGuard, RolesGuard)
export class CoursesController {
  constructor(private coursesService: CoursesService) {}

  @Get()
  async findAll(@Query() query: ListCoursesDto) {
    const courses = await this.coursesService.findAll(query);
    return { success: true, data: courses, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const course = await this.coursesService.findOne(id);
    return { success: true, data: course, message: 'Success' };
  }

  // Course dibuat & dikelola TEACHER saja (bukan ADMIN) -- Course.teacherId
  // wajib diisi di schema dan ADMIN tidak punya TeacherProfile, jadi
  // secara desain course selalu punya pemilik teacher yang jelas.
  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateCourseDto) {
    const course = await this.coursesService.create(user.userId, dto);
    return { success: true, data: course, message: 'Course berhasil dibuat' };
  }

  @Put(':id')
  @Roles('TEACHER')
  async update(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateCourseDto,
  ) {
    const course = await this.coursesService.update(user.userId, id, dto);
    return { success: true, data: course, message: 'Course berhasil diperbarui' };
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/courses/courses.service.ts")"
echo ">> Menulis src/courses/courses.service.ts"
cat > src/courses/courses.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCourseDto } from './dto/create-course.dto';
import { UpdateCourseDto } from './dto/update-course.dto';
import { ListCoursesDto } from './dto/list-courses.dto';

@Injectable()
export class CoursesService {
  constructor(private prisma: PrismaService) {}

  // Default cuma PUBLISHED (siswa tidak perlu lihat draft) -- sama pola
  // dengan `includeInactive` di SubjectsService, tinggal kirim ?status=
  // eksplisit kalau butuh lihat DRAFT/ARCHIVED (mis. teacher lihat draft-nya sendiri).
  async findAll(query: ListCoursesDto) {
    return this.prisma.course.findMany({
      where: {
        subjectId: query.subjectId,
        teacherId: query.teacherId,
        status: query.status ?? 'PUBLISHED',
      },
      include: { teacher: { select: { id: true, name: true } }, _count: { select: { lessons: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: number) {
    const course = await this.prisma.course.findUnique({
      where: { id },
      include: {
        lessons: { orderBy: { sequence: 'asc' } },
        teacher: { select: { id: true, name: true } },
      },
    });

    if (!course) {
      throw new NotFoundException('Course tidak ditemukan.');
    }

    return course;
  }

  async create(userId: number, dto: CreateCourseDto) {
    const profile = await this.findTeacherProfile(userId);

    const subject = await this.prisma.subject.findUnique({ where: { id: dto.subjectId } });
    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    return this.prisma.course.create({
      data: { subjectId: dto.subjectId, teacherId: profile.id, title: dto.title },
    });
  }

  async update(userId: number, id: number, dto: UpdateCourseDto) {
    const profile = await this.findTeacherProfile(userId);

    const course = await this.prisma.course.findUnique({ where: { id } });
    if (!course) {
      throw new NotFoundException('Course tidak ditemukan.');
    }
    if (course.teacherId !== profile.id) {
      throw new ForbiddenException('Kamu bukan pemilik course ini.');
    }

    return this.prisma.course.update({ where: { id }, data: dto });
  }

  async findTeacherProfile(userId: number) {
    const profile = await this.prisma.teacherProfile.findUnique({ where: { userId } });
    if (!profile) {
      throw new NotFoundException('Profil teacher tidak ditemukan.');
    }
    return profile;
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/courses/dto/create-course.dto.ts")"
echo ">> Menulis src/courses/dto/create-course.dto.ts"
cat > src/courses/dto/create-course.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsInt, IsString } from 'class-validator';

export class CreateCourseDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  title!: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/courses/dto/update-course.dto.ts")"
echo ">> Menulis src/courses/dto/update-course.dto.ts"
cat > src/courses/dto/update-course.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn, IsOptional, IsString } from 'class-validator';

export class UpdateCourseDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsIn(['DRAFT', 'PUBLISHED', 'ARCHIVED'])
  status?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/courses/dto/list-courses.dto.ts")"
echo ">> Menulis src/courses/dto/list-courses.dto.ts"
cat > src/courses/dto/list-courses.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString } from 'class-validator';

export class ListCoursesDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  teacherId?: number;

  // Default service hanya kembalikan PUBLISHED untuk non-owner/non-admin --
  // lihat CoursesService.findAll().
  @IsOptional()
  @IsString()
  status?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/lessons/lessons.module.ts")"
echo ">> Menulis src/lessons/lessons.module.ts"
cat > src/lessons/lessons.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { CoursesModule } from '../courses/courses.module';
import { LessonsController } from './lessons.controller';
import { LessonsService } from './lessons.service';

@Module({
  imports: [CoursesModule],
  controllers: [LessonsController],
  providers: [LessonsService],
  exports: [LessonsService],
})
export class LessonsModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/lessons/lessons.controller.ts")"
echo ">> Menulis src/lessons/lessons.controller.ts"
cat > src/lessons/lessons.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
import { LessonsService } from './lessons.service';
import { CreateLessonDto } from './dto/create-lesson.dto';
import { UpdateLessonDto } from './dto/update-lesson.dto';
import { ListLessonsDto } from './dto/list-lessons.dto';

@Controller('lessons')
@UseGuards(JwtAuthGuard, RolesGuard)
export class LessonsController {
  constructor(private lessonsService: LessonsService) {}

  @Get()
  async findAll(@Query() query: ListLessonsDto) {
    const lessons = await this.lessonsService.findAll(query);
    return { success: true, data: lessons, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const lesson = await this.lessonsService.findOne(id);
    return { success: true, data: lesson, message: 'Success' };
  }

  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateLessonDto) {
    const lesson = await this.lessonsService.create(user.userId, dto);
    return { success: true, data: lesson, message: 'Lesson berhasil dibuat' };
  }

  @Put(':id')
  @Roles('TEACHER')
  async update(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateLessonDto,
  ) {
    const lesson = await this.lessonsService.update(user.userId, id, dto);
    return { success: true, data: lesson, message: 'Lesson berhasil diperbarui' };
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/lessons/lessons.service.ts")"
echo ">> Menulis src/lessons/lessons.service.ts"
cat > src/lessons/lessons.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CoursesService } from '../courses/courses.service';
import { CreateLessonDto } from './dto/create-lesson.dto';
import { UpdateLessonDto } from './dto/update-lesson.dto';
import { ListLessonsDto } from './dto/list-lessons.dto';

@Injectable()
export class LessonsService {
  constructor(
    private prisma: PrismaService,
    private coursesService: CoursesService,
  ) {}

  async findAll(query: ListLessonsDto) {
    return this.prisma.lesson.findMany({
      where: { courseId: query.courseId },
      orderBy: { sequence: 'asc' },
    });
  }

  async findOne(id: number) {
    const lesson = await this.prisma.lesson.findUnique({
      where: { id },
      include: { materials: true, course: true },
    });

    if (!lesson) {
      throw new NotFoundException('Lesson tidak ditemukan.');
    }

    return lesson;
  }

  async create(userId: number, dto: CreateLessonDto) {
    const course = await this.ensureOwnedCourse(userId, dto.courseId);

    if (dto.topicId) {
      const topic = await this.prisma.topic.findUnique({ where: { id: dto.topicId } });
      if (!topic) {
        throw new NotFoundException('Topic tidak ditemukan.');
      }
    }

    return this.prisma.lesson.create({
      data: {
        courseId: course.id,
        topicId: dto.topicId,
        title: dto.title,
        sequence: dto.sequence ?? 0,
      },
    });
  }

  async update(userId: number, id: number, dto: UpdateLessonDto) {
    const lesson = await this.prisma.lesson.findUnique({ where: { id } });
    if (!lesson) {
      throw new NotFoundException('Lesson tidak ditemukan.');
    }

    await this.ensureOwnedCourse(userId, lesson.courseId);

    return this.prisma.lesson.update({ where: { id }, data: dto });
  }

  // Lesson selalu berada "di dalam" sebuah course -- ownership-nya
  // diturunkan dari siapa pemilik course itu, bukan dicek terpisah.
  private async ensureOwnedCourse(userId: number, courseId: number) {
    const profile = await this.coursesService.findTeacherProfile(userId);

    const course = await this.prisma.course.findUnique({ where: { id: courseId } });
    if (!course) {
      throw new NotFoundException('Course tidak ditemukan.');
    }
    if (course.teacherId !== profile.id) {
      throw new ForbiddenException('Kamu bukan pemilik course ini.');
    }

    return course;
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/lessons/dto/create-lesson.dto.ts")"
echo ">> Menulis src/lessons/dto/create-lesson.dto.ts"
cat > src/lessons/dto/create-lesson.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateLessonDto {
  @IsInt()
  courseId!: number;

  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsString()
  title!: string;

  @IsOptional()
  @IsInt()
  sequence?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/lessons/dto/update-lesson.dto.ts")"
echo ">> Menulis src/lessons/dto/update-lesson.dto.ts"
cat > src/lessons/dto/update-lesson.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn, IsInt, IsOptional, IsString } from 'class-validator';

export class UpdateLessonDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsInt()
  sequence?: number;

  @IsOptional()
  @IsIn(['DRAFT', 'PUBLISHED', 'ARCHIVED'])
  status?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/lessons/dto/list-lessons.dto.ts")"
echo ">> Menulis src/lessons/dto/list-lessons.dto.ts"
cat > src/lessons/dto/list-lessons.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListLessonsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  courseId?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/materials/materials.module.ts")"
echo ">> Menulis src/materials/materials.module.ts"
cat > src/materials/materials.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { CoursesModule } from '../courses/courses.module';
import { MaterialsController } from './materials.controller';
import { MaterialsService } from './materials.service';

@Module({
  imports: [CoursesModule],
  controllers: [MaterialsController],
  providers: [MaterialsService],
})
export class MaterialsModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/materials/materials.controller.ts")"
echo ">> Menulis src/materials/materials.controller.ts"
cat > src/materials/materials.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
import { MaterialsService } from './materials.service';
import { CreateMaterialDto } from './dto/create-material.dto';
import { UpdateMaterialDto } from './dto/update-material.dto';
import { ListMaterialsDto } from './dto/list-materials.dto';

@Controller('materials')
@UseGuards(JwtAuthGuard, RolesGuard)
export class MaterialsController {
  constructor(private materialsService: MaterialsService) {}

  @Get()
  async findAll(@Query() query: ListMaterialsDto) {
    const materials = await this.materialsService.findAll(query);
    return { success: true, data: materials, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const material = await this.materialsService.findOne(id);
    return { success: true, data: material, message: 'Success' };
  }

  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateMaterialDto) {
    const material = await this.materialsService.create(user.userId, dto);
    return { success: true, data: material, message: 'Learning material berhasil dibuat' };
  }

  @Put(':id')
  @Roles('TEACHER')
  async update(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateMaterialDto,
  ) {
    const material = await this.materialsService.update(user.userId, id, dto);
    return { success: true, data: material, message: 'Learning material berhasil diperbarui' };
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/materials/materials.service.ts")"
echo ">> Menulis src/materials/materials.service.ts"
cat > src/materials/materials.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CoursesService } from '../courses/courses.service';
import { CreateMaterialDto } from './dto/create-material.dto';
import { UpdateMaterialDto } from './dto/update-material.dto';
import { ListMaterialsDto } from './dto/list-materials.dto';

@Injectable()
export class MaterialsService {
  constructor(
    private prisma: PrismaService,
    private coursesService: CoursesService,
  ) {}

  async findAll(query: ListMaterialsDto) {
    return this.prisma.learningMaterial.findMany({
      where: { lessonId: query.lessonId },
      orderBy: { createdAt: 'asc' },
    });
  }

  async findOne(id: number) {
    const material = await this.prisma.learningMaterial.findUnique({ where: { id } });
    if (!material) {
      throw new NotFoundException('Learning material tidak ditemukan.');
    }
    return material;
  }

  async create(userId: number, dto: CreateMaterialDto) {
    await this.ensureOwnedLesson(userId, dto.lessonId);

    return this.prisma.learningMaterial.create({
      data: {
        lessonId: dto.lessonId,
        title: dto.title,
        type: dto.type,
        content: dto.content,
        resourceUrl: dto.resourceUrl,
      },
    });
  }

  async update(userId: number, id: number, dto: UpdateMaterialDto) {
    const material = await this.prisma.learningMaterial.findUnique({ where: { id } });
    if (!material) {
      throw new NotFoundException('Learning material tidak ditemukan.');
    }

    await this.ensureOwnedLesson(userId, material.lessonId);

    return this.prisma.learningMaterial.update({ where: { id }, data: dto });
  }

  // Material -> Lesson -> Course -> teacherId. Rantai kepemilikan diturunkan
  // dari root-nya (course), bukan dicek per-level terpisah.
  private async ensureOwnedLesson(userId: number, lessonId: number) {
    const profile = await this.coursesService.findTeacherProfile(userId);

    const lesson = await this.prisma.lesson.findUnique({
      where: { id: lessonId },
      include: { course: true },
    });
    if (!lesson) {
      throw new NotFoundException('Lesson tidak ditemukan.');
    }
    if (lesson.course.teacherId !== profile.id) {
      throw new ForbiddenException('Kamu bukan pemilik course dari lesson ini.');
    }
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/materials/dto/create-material.dto.ts")"
echo ">> Menulis src/materials/dto/create-material.dto.ts"
cat > src/materials/dto/create-material.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn, IsInt, IsOptional, IsString } from 'class-validator';

export class CreateMaterialDto {
  @IsInt()
  lessonId!: number;

  @IsString()
  title!: string;

  @IsIn(['VIDEO', 'TEXT', 'PDF', 'LINK'])
  type!: string;

  @IsOptional()
  @IsString()
  content?: string;

  @IsOptional()
  @IsString()
  resourceUrl?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/materials/dto/update-material.dto.ts")"
echo ">> Menulis src/materials/dto/update-material.dto.ts"
cat > src/materials/dto/update-material.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn, IsOptional, IsString } from 'class-validator';

export class UpdateMaterialDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsIn(['VIDEO', 'TEXT', 'PDF', 'LINK'])
  type?: string;

  @IsOptional()
  @IsString()
  content?: string;

  @IsOptional()
  @IsString()
  resourceUrl?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/materials/dto/list-materials.dto.ts")"
echo ">> Menulis src/materials/dto/list-materials.dto.ts"
cat > src/materials/dto/list-materials.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListMaterialsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  lessonId?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/admin/admin.module.ts")"
echo ">> Menulis src/admin/admin.module.ts"
cat > src/admin/admin.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  controllers: [AdminController],
  providers: [AdminService],
})
export class AdminModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/admin/admin.controller.ts")"
echo ">> Menulis src/admin/admin.controller.ts"
cat > src/admin/admin.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AdminService } from './admin.service';
import { ListUsersDto } from './dto/list-users.dto';
import { UpdateUserStatusDto } from './dto/update-user-status.dto';

@Controller('admin/users')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
export class AdminController {
  constructor(private adminService: AdminService) {}

  @Get()
  async findAll(@Query() query: ListUsersDto) {
    const users = await this.adminService.findAll(query);
    return { success: true, data: users, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const user = await this.adminService.findOne(id);
    return { success: true, data: user, message: 'Success' };
  }

  @Put(':id/status')
  async updateStatus(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserStatusDto,
  ) {
    const updated = await this.adminService.updateStatus(user.userId, id, dto);
    return { success: true, data: updated, message: 'Status user berhasil diperbarui' };
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/admin/admin.service.ts")"
echo ">> Menulis src/admin/admin.service.ts"
cat > src/admin/admin.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/admin/dto/update-user-status.dto.ts")"
echo ">> Menulis src/admin/dto/update-user-status.dto.ts"
cat > src/admin/dto/update-user-status.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn } from 'class-validator';

export class UpdateUserStatusDto {
  @IsIn(['ACTIVE', 'SUSPENDED', 'DEACTIVATED'])
  status!: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/admin/dto/list-users.dto.ts")"
echo ">> Menulis src/admin/dto/list-users.dto.ts"
cat > src/admin/dto/list-users.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsIn, IsOptional } from 'class-validator';

export class ListUsersDto {
  @IsOptional()
  @IsIn(['STUDENT', 'TEACHER', 'ADMIN', 'PARENT', 'TUTOR', 'PROFESSIONAL'])
  role?: string;

  @IsOptional()
  @IsIn(['ACTIVE', 'SUSPENDED', 'DEACTIVATED'])
  status?: string;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/common/services/audit-log.service.ts")"
echo ">> Menulis src/common/services/audit-log.service.ts"
cat > src/common/services/audit-log.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/diagnostics/diagnostics.service.ts")"
echo ">> Menulis src/diagnostics/diagnostics.service.ts"
cat > src/diagnostics/diagnostics.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EvidenceService } from '../learning-engine/evidence/evidence.service';
import { MasteryService } from '../learning-engine/mastery/mastery.service';
import type { UpdateCompetencyResult } from '../learning-engine/mastery/mastery.service';
import { CompetencySnapshotService } from '../learning-engine/snapshots/competency-snapshot.service';
import { LearningEngineConfigService } from '../learning-engine/config/learning-engine-config.service';
import { LearningPathReconciler } from '../learning-engine/learning-path/learning-path-reconciler';
import { SubmitDiagnosticDto } from './dto/submit-diagnostic.dto';
import { CreateDiagnosticTestDto } from './dto/create-diagnostic-test.dto';
import { detectSuspiciousTiming } from '../learning-engine/integrity/suspicious-timing-detector';

@Injectable()
export class DiagnosticsService {
  constructor(
    private prisma: PrismaService,
    private evidenceService: EvidenceService,
    private masteryService: MasteryService,
    private competencySnapshotService: CompetencySnapshotService,
    private learningEngineConfigService: LearningEngineConfigService,
    private learningPathReconciler: LearningPathReconciler,
  ) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({ where: { userId } });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  // Keputusan bisnis (16 Agustus 2026): diagnostic test itu "titik awal"
  // (starting point) buat learning path siswa, BUKAN latihan yang boleh
  // diulang bebas -- kalau boleh diulang tanpa batas, siswa bisa "diagnostic
  // shopping" (coba berkali-kali sampai dapat hasil yang menguntungkan).
  // Assessment TIDAK kena aturan ini (lihat AssessmentsService) -- itu
  // memang harus boleh diulang, beda peran dengan diagnostic.
  //
  // diagnosticTest.allowMultipleAttempts (default false) bisa override
  // cap ini per-test tanpa migration/rewrite lagi -- lihat komentar di
  // schema.prisma (forward-compat untuk Teacher Engine).
  async startAttempt(userId: number, diagnosticTestId: number) {
    const profile = await this.findProfileByUserId(userId);

    const diagnosticTest = await this.prisma.diagnosticTest.findUnique({
      where: { id: diagnosticTestId },
    });

    if (!diagnosticTest) {
      throw new NotFoundException('Diagnostic test tidak ditemukan.');
    }

    const latestAttempt = await this.prisma.diagnosticAttempt.findFirst({
      where: { diagnosticTestId, studentId: profile.id },
      orderBy: { startedAt: 'desc' },
    });

    if (!diagnosticTest.allowMultipleAttempts && latestAttempt?.status === 'SUBMITTED') {
      throw new ConflictException(
        'Kamu sudah menyelesaikan diagnostic test ini. Diagnostic test hanya bisa dikerjakan sekali -- hubungi guru/admin kalau butuh mengulang.',
      );
    }

    // Attempt lama masih IN_PROGRESS (mis. tab ditutup sebelum submit) --
    // lanjutkan attempt yang sama, jangan bikin duplikat. Berlaku baik
    // cap-nya aktif maupun tidak.
    if (latestAttempt?.status === 'IN_PROGRESS') {
      return latestAttempt;
    }

    const previousAttemptsCount = await this.prisma.diagnosticAttempt.count({
      where: { diagnosticTestId, studentId: profile.id },
    });

    return this.prisma.diagnosticAttempt.create({
      data: {
        diagnosticTestId,
        studentId: profile.id,
        attemptNumber: previousAttemptsCount + 1,
        status: 'IN_PROGRESS',
      },
    });
  }

  // ADMIN/TEACHER only (ditegakkan di controller lewat @Roles). "Void"
  // dipilih daripada delete supaya riwayat attempt asli tetap bisa
  // ditelusuri -- siapa yang reset, kapan, dan alasannya apa.
  async voidAttempt(actorUserId: number, attemptId: number, reason?: string) {
    const attempt = await this.prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });

    if (!attempt) {
      throw new NotFoundException('Attempt tidak ditemukan.');
    }

    if (attempt.status === 'VOID') {
      throw new ConflictException('Attempt ini sudah di-void sebelumnya.');
    }

    return this.prisma.diagnosticAttempt.update({
      where: { id: attemptId },
      data: {
        status: 'VOID',
        voidedAt: new Date(),
        voidReason: reason,
        voidedByUserId: actorUserId,
      },
    });
  }

  // Gap Phase 4 (19 Agustus 2026): sebelum ini TIDAK ADA endpoint sama
  // sekali untuk membuat DiagnosticTest baru -- satu-satunya cara cuma
  // lewat seed script manual. ADMIN-only karena DiagnosticTest tidak
  // punya teacherId di schema (platform-level, bukan milik teacher
  // tertentu) -- konsisten dengan section 5.4 dokumen master.
  async createTest(dto: CreateDiagnosticTestDto) {
    const subject = await this.prisma.subject.findUnique({ where: { id: dto.subjectId } });
    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    const uniqueQuestionIds = [...new Set(dto.questionIds)];
    const questions = await this.prisma.question.findMany({
      where: { id: { in: uniqueQuestionIds } },
    });
    if (questions.length !== uniqueQuestionIds.length) {
      throw new BadRequestException('Ada questionId yang tidak valid/tidak ditemukan.');
    }

    return this.prisma.diagnosticTest.create({
      data: {
        subjectId: dto.subjectId,
        name: dto.name,
        durationMinutes: dto.durationMinutes,
        allowMultipleAttempts: dto.allowMultipleAttempts ?? false,
        questions: {
          create: uniqueQuestionIds.map((questionId, index) => ({
            questionId,
            sequence: index,
          })),
        },
      },
      include: { questions: true },
    });
  }

  /**
   * Alur 17 langkah sesuai spec Phase 4 bagian 12, semuanya dalam SATU
   * database transaction (bagian 14: "harus diproses dalam satu database
   * transaction ... jangan sampai answer berhasil masuk tapi
   * StudentCompetency gagal update").
   */
  async submit(userId: number, diagnosticTestId: number, dto: SubmitDiagnosticDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.$transaction(async (tx) => {
      // 2. Validate attempt ownership
      const attempt = await tx.diagnosticAttempt.findUnique({
        where: { id: dto.attemptId },
      });

      if (!attempt) {
        throw new NotFoundException('Attempt tidak ditemukan.');
      }
      if (attempt.studentId !== profile.id) {
        throw new ForbiddenException('Attempt ini bukan milik kamu.');
      }
      if (attempt.diagnosticTestId !== diagnosticTestId) {
        throw new BadRequestException('Attempt ini bukan untuk diagnostic test ini.');
      }

      // 3. Validate attempt status -- idempotency guard yang ATOMIC.
      // UPDATE ... WHERE status='IN_PROGRESS' mengunci baris ini di dalam
      // transaction; kalau ada request submit kedua (double-klik/retry)
      // yang datang bersamaan, salah satunya pasti dapat count=0 di sini
      // dan gagal SEBELUM sempat memproses jawaban apa pun.
      const guarded = await tx.diagnosticAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException('Attempt ini sudah pernah disubmit sebelumnya.');
      }

      // 4. Validate submitted answers -- questionId harus benar-benar
      // bagian dari diagnostic test ini (bukan soal dari test lain).
      const validQuestions = await tx.diagnosticQuestion.findMany({
        where: { diagnosticTestId },
        select: { questionId: true },
      });
      const validQuestionIds = new Set(validQuestions.map((q) => q.questionId));

      for (const answer of dto.answers) {
        if (!validQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari diagnostic test ini.`,
          );
        }
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness.
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } = await this.evidenceService.loadAndAggregate(
        tx,
        normalizedAnswers,
      );

      // 8. Insert DiagnosticAnswer (bulk, bukan satu-satu).
      await tx.diagnosticAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          timeSpentSeconds: a.timeSpentSeconds ?? undefined,
        })),
      });

      // 9-14. Per competency yang tersentuh: EMA mastery, confidence,
      // classify bucket, snapshot, dan reconcile learning path HANYA kalau
      // bucket-nya berubah.
      const config = await this.learningEngineConfigService.getActiveConfig(tx);
      const competencyResults: UpdateCompetencyResult[] = [];

      for (const [competencyId, evidence] of evidenceByCompetency) {
        const result = await this.masteryService.updateForCompetency(tx, {
          studentId: profile.id,
          competencyId,
          evidence,
          config,
        });

        await this.competencySnapshotService.create(tx, {
          studentId: profile.id,
          competencyId,
          masteryScore: result.newMasteryScore,
          confidenceScore: result.newConfidenceScore,
          totalAnswered: result.totalAnswered,
          totalCorrect: result.totalCorrect,
          masteryBucket: result.newBucket,
          triggeredByAttemptId: attempt.id,
          sourceType: 'DIAGNOSTIC',
          engineVersion: config.engineVersion,
          configVersion: config.configVersion,
        });

        if (result.bucketChanged) {
          await this.learningPathReconciler.reconcile(tx, {
            studentId: profile.id,
            competencyId,
            oldBucket: result.oldBucket,
            newBucket: result.newBucket,
          });
        }

        competencyResults.push(result);
      }

      // 15. Update DiagnosticAttempt -- score & completedAt (status sudah
      // SUBMITTED dari guard di step 3). Skor attempt ini SENGAJA dipisah
      // dari masteryScore (spec bagian 21: Assessment Score != Mastery
      // Score) -- ini murni persentase benar di attempt ini saja, tanpa
      // difficulty weighting maupun EMA.
      const correctCount = enrichedAnswers.filter((a) => a.isCorrect).length;
      const overallScore = (correctCount / enrichedAnswers.length) * 100;

      // Sesi 6: deteksi timing mencurigakan -- rule-based, murni fungsi,
      // dievaluasi dari jawaban attempt ini saja.
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      // Keputusan bisnis (16 Agustus 2026, item #3): durationMinutes DITEGAKKAN
      // sebagai SOFT FLAG, bukan blokir keras -- attempt yang telat tetap
      // diterima & tetap dihitung skornya (siswa tidak dihukum kalau
      // internetnya lelet), tapi ditandai isFlagged supaya guru/admin bisa
      // menilai sendiri lewat data, bukan lewat sistem yang menolak mentah-mentah.
      const diagnosticTest = await tx.diagnosticTest.findUnique({
        where: { id: diagnosticTestId },
        select: { durationMinutes: true },
      });
      const elapsedMinutes = (Date.now() - attempt.startedAt.getTime()) / 60_000;
      const isOverDuration =
        diagnosticTest?.durationMinutes != null &&
        elapsedMinutes > diagnosticTest.durationMinutes;

      const flagReasons = [
        ...(timingCheck.isFlagged && timingCheck.flagReason ? [timingCheck.flagReason] : []),
        ...(isOverDuration
          ? [
              `Melebihi batas waktu pengerjaan (${diagnosticTest!.durationMinutes} menit, selesai dalam ${Math.round(elapsedMinutes)} menit).`,
            ]
          : []),
      ];
      const isFlagged = timingCheck.isFlagged || isOverDuration;

      const updatedAttempt = await tx.diagnosticAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(isFlagged
            ? {
                isFlagged: true,
                flagReason: flagReasons.join(' | '),
                flaggedAt: new Date(),
              }
            : {}),
        },
      });

      // 17. Return learning profile.
      return {
        attempt: updatedAttempt,
        overallScore,
        competencyResults,
      };
    });
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/diagnostics/diagnostics.controller.ts")"
echo ">> Menulis src/diagnostics/diagnostics.controller.ts"
cat > src/diagnostics/diagnostics.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/diagnostics/dto/create-diagnostic-test.dto.ts")"
echo ">> Menulis src/diagnostics/dto/create-diagnostic-test.dto.ts"
cat > src/diagnostics/dto/create-diagnostic-test.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
} from 'class-validator';

export class CreateDiagnosticTestDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  name!: string;

  @IsOptional()
  @IsInt()
  durationMinutes?: number;

  @IsOptional()
  @IsBoolean()
  allowMultipleAttempts?: boolean;

  @IsArray()
  @ArrayMinSize(1)
  @Type(() => Number)
  @IsInt({ each: true })
  questionIds!: number[];
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/assessments/assessments.service.ts")"
echo ">> Menulis src/assessments/assessments.service.ts"
cat > src/assessments/assessments.service.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EvidenceService } from '../learning-engine/evidence/evidence.service';
import { MasteryService } from '../learning-engine/mastery/mastery.service';
import type { UpdateCompetencyResult } from '../learning-engine/mastery/mastery.service';
import { CompetencySnapshotService } from '../learning-engine/snapshots/competency-snapshot.service';
import { LearningEngineConfigService } from '../learning-engine/config/learning-engine-config.service';
import { LearningPathReconciler } from '../learning-engine/learning-path/learning-path-reconciler';
import { SubmitAssessmentDto } from './dto/submit-assessment.dto';
import { CreateAssessmentDto } from './dto/create-assessment.dto';
import { detectSuspiciousTiming } from '../learning-engine/integrity/suspicious-timing-detector';

@Injectable()
export class AssessmentsService {
  constructor(
    private prisma: PrismaService,
    private evidenceService: EvidenceService,
    private masteryService: MasteryService,
    private competencySnapshotService: CompetencySnapshotService,
    private learningEngineConfigService: LearningEngineConfigService,
    private learningPathReconciler: LearningPathReconciler,
  ) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({
      where: { userId },
    });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  // Keputusan bisnis (16 Agustus 2026): assessment BOLEH diulang -- beda
  // peran dari diagnostic (lihat DiagnosticsService.startAttempt). Ini
  // memang cara sistem "belajar" tentang perkembangan siswa dari waktu ke
  // waktu (confidence naik pelan-pelan lewat EMA seiring makin banyak
  // evidence masuk). Yang dibatasi bukan JUMLAH ulangnya, tapi JEDANYA --
  // supaya siswa tidak spam submit berkali-kali dalam semenit cuma buat
  // menggelembungkan confidence score secara artifisial, bukan belajar beneran.
  //
  // Ini DEFAULT fallback -- assessment.cooldownHours (nullable) bisa
  // override per-item kalau nanti Teacher Engine butuh itu, tanpa
  // migration/rewrite lagi (lihat komentar di schema.prisma).
  private static readonly DEFAULT_ATTEMPT_COOLDOWN_HOURS = 24;

  async startAttempt(userId: number, assessmentId: number) {
    const profile = await this.findProfileByUserId(userId);

    const assessment = await this.prisma.assessment.findUnique({
      where: { id: assessmentId },
    });

    if (!assessment) {
      throw new NotFoundException('Assessment tidak ditemukan.');
    }

    const latestAttempt = await this.prisma.assessmentAttempt.findFirst({
      where: { assessmentId, studentId: profile.id },
      orderBy: { startedAt: 'desc' },
    });

    // Attempt lama masih IN_PROGRESS -- lanjutkan yang sama, jangan bikin duplikat.
    if (latestAttempt?.status === 'IN_PROGRESS') {
      return latestAttempt;
    }

    if (latestAttempt?.status === 'SUBMITTED' && latestAttempt.completedAt) {
      const cooldownHours =
        assessment.cooldownHours ??
        AssessmentsService.DEFAULT_ATTEMPT_COOLDOWN_HOURS;
      const hoursSinceLastAttempt =
        (Date.now() - latestAttempt.completedAt.getTime()) / 3_600_000;

      if (hoursSinceLastAttempt < cooldownHours) {
        const hoursRemaining = Math.ceil(cooldownHours - hoursSinceLastAttempt);
        throw new ConflictException(
          `Kamu baru saja mengerjakan assessment ini. Coba lagi dalam ${hoursRemaining} jam.`,
        );
      }
    }

    const previousAttemptsCount = await this.prisma.assessmentAttempt.count({
      where: { assessmentId, studentId: profile.id },
    });

    return this.prisma.assessmentAttempt.create({
      data: {
        assessmentId,
        studentId: profile.id,
        attemptNumber: previousAttemptsCount + 1,
        status: 'IN_PROGRESS',
      },
    });
  }

  /**
   * Sama persis alurnya dengan DiagnosticsService.submit() -- keduanya
   * memakai Learning Engine yang sama (spec Phase 4 bagian 13: "Jangan
   * membuat algoritma mastery berbeda antara Diagnostic dan Assessment").
   *
   * SATU perbedaan struktural: skor attempt di sini dihitung berbobot
   * `points` per soal (field yang memang cuma ada di AssessmentQuestion,
   * tidak ada di DiagnosticQuestion) -- bukan sekadar persen jawaban
   * benar seperti di diagnostic. Ini tetap "Assessment Score", BUKAN
   * "Mastery Score" (section 21) -- masteryScore tetap dihitung EMA lewat
   * MasteryService yang identik dengan diagnostic.
   */
  async submit(userId: number, assessmentId: number, dto: SubmitAssessmentDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.$transaction(async (tx) => {
      // 2. Validate attempt ownership
      const attempt = await tx.assessmentAttempt.findUnique({
        where: { id: dto.attemptId },
      });

      if (!attempt) {
        throw new NotFoundException('Attempt tidak ditemukan.');
      }
      if (attempt.studentId !== profile.id) {
        throw new ForbiddenException('Attempt ini bukan milik kamu.');
      }
      if (attempt.assessmentId !== assessmentId) {
        throw new BadRequestException(
          'Attempt ini bukan untuk assessment ini.',
        );
      }

      // 3. Validate attempt status -- idempotency guard ATOMIC, sama
      // persis polanya dengan DiagnosticsService.
      const guarded = await tx.assessmentAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException(
          'Attempt ini sudah pernah disubmit sebelumnya.',
        );
      }

      // 4. Validate submitted answers + sekaligus ambil `points` per soal
      // dalam SATU query (bukan dua query terpisah untuk validasi dan
      // untuk ambil points). Juga tolak questionId yang dikirim berulang
      // dalam satu payload (fix Bug #2 QA audit 16 Agustus 2026 -- pola
      // sama persis dengan DiagnosticsService).
      const assessmentQuestions = await tx.assessmentQuestion.findMany({
        where: { assessmentId },
        select: { questionId: true, points: true },
      });
      const pointsByQuestionId = new Map(
        assessmentQuestions.map((q) => [q.questionId, Number(q.points)]),
      );
      const seenQuestionIds = new Set<number>();

      for (const answer of dto.answers) {
        if (!pointsByQuestionId.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari assessment ini.`,
          );
        }
        if (seenQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} dikirim lebih dari sekali dalam satu submission.`,
          );
        }
        seenQuestionIds.add(answer.questionId);
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness -- SAMA PERSIS dengan diagnostic,
      // service yang dipakai pun sama (EvidenceService).
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } =
        await this.evidenceService.loadAndAggregate(tx, normalizedAnswers);

      // 8. Insert AssessmentAnswer (bulk), sekalian hitung pointsEarned
      // per jawaban dari map yang sudah di-load di step 4.
      await tx.assessmentAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          pointsEarned: a.isCorrect
            ? (pointsByQuestionId.get(a.questionId) ?? 0)
            : 0,
          timeSpentSeconds: a.timeSpentSeconds ?? undefined,
        })),
      });

      // 9-14. Per competency yang tersentuh: EMA mastery, confidence,
      // classify bucket, snapshot, reconcile learning path -- LEARNING
      // ENGINE YANG SAMA dengan diagnostic, cuma sourceType-nya beda.
      const config = await this.learningEngineConfigService.getActiveConfig(tx);
      const competencyResults: UpdateCompetencyResult[] = [];

      for (const [competencyId, evidence] of evidenceByCompetency) {
        const result = await this.masteryService.updateForCompetency(tx, {
          studentId: profile.id,
          competencyId,
          evidence,
          config,
        });

        await this.competencySnapshotService.create(tx, {
          studentId: profile.id,
          competencyId,
          masteryScore: result.newMasteryScore,
          confidenceScore: result.newConfidenceScore,
          totalAnswered: result.totalAnswered,
          totalCorrect: result.totalCorrect,
          masteryBucket: result.newBucket,
          triggeredByAttemptId: attempt.id,
          sourceType: 'ASSESSMENT',
          engineVersion: config.engineVersion,
          configVersion: config.configVersion,
        });

        if (result.bucketChanged) {
          await this.learningPathReconciler.reconcile(tx, {
            studentId: profile.id,
            competencyId,
            oldBucket: result.oldBucket,
            newBucket: result.newBucket,
          });
        }

        competencyResults.push(result);
      }

      // 15. Update AssessmentAttempt -- score berbobot points (BUKAN
      // masteryScore), & completedAt.
      let totalPossiblePoints = 0;
      let totalEarnedPoints = 0;

      for (const a of enrichedAnswers) {
        const possible = pointsByQuestionId.get(a.questionId) ?? 0;
        totalPossiblePoints += possible;
        if (a.isCorrect) {
          totalEarnedPoints += possible;
        }
      }

      const overallScore =
        totalPossiblePoints > 0
          ? (totalEarnedPoints / totalPossiblePoints) * 100
          : 0;

      // Sesi 6: deteksi timing mencurigakan -- pola identik dengan
      // DiagnosticsService, fungsi pure yang sama-sama di-reuse.
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      // Keputusan bisnis (16 Agustus 2026, item #3): sama seperti diagnostic
      // -- durationMinutes jadi SOFT FLAG, bukan blokir keras. Assessment di
      // Kelasxtra berperan sebagai latihan/check-in berkala (bukan ujian
      // formal sekali-jalan), jadi menolak submit yang telat bertentangan
      // dengan tujuan mendorong siswa terus berlatih.
      const assessment = await tx.assessment.findUnique({
        where: { id: assessmentId },
        select: { durationMinutes: true },
      });
      const elapsedMinutes =
        (Date.now() - attempt.startedAt.getTime()) / 60_000;
      const isOverDuration =
        assessment?.durationMinutes != null &&
        elapsedMinutes > assessment.durationMinutes;

      const flagReasons = [
        ...(timingCheck.isFlagged && timingCheck.flagReason
          ? [timingCheck.flagReason]
          : []),
        ...(isOverDuration
          ? [
              `Melebihi batas waktu pengerjaan (${assessment!.durationMinutes} menit, selesai dalam ${Math.round(elapsedMinutes)} menit).`,
            ]
          : []),
      ];
      const isFlagged = timingCheck.isFlagged || isOverDuration;

      const updatedAttempt = await tx.assessmentAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(isFlagged
            ? {
                isFlagged: true,
                flagReason: flagReasons.join(' | '),
                flaggedAt: new Date(),
              }
            : {}),
        },
      });

      // 17. Return learning profile.
      return {
        attempt: updatedAttempt,
        overallScore,
        competencyResults,
      };
    });
  }

  // Fix #9 (QA audit 16 Agustus 2026): sebelumnya hasil assessment CUMA
  // ada di response submit() sekali itu saja -- kalau siswa nutup
  // halamannya atau mau lihat lagi besok, tidak ada cara sama sekali.
  // Endpoint ini disebut eksplisit di dokumen master (section 12.6) tapi
  // belum pernah diimplementasikan.
  //
  // Tanpa query attemptId -> ambil attempt SUBMITTED paling baru untuk
  // assessment ini (hasil "current" yang paling relevan buat siswa).
  // Dengan attemptId -> lihat attempt spesifik (riwayat, karena sekarang
  // assessment boleh diulang -- lihat startAttempt).
  async getResults(userId: number, assessmentId: number, attemptId?: number) {
    const profile = await this.findProfileByUserId(userId);

    const attempt = attemptId
      ? await this.prisma.assessmentAttempt.findUnique({
          where: { id: attemptId },
        })
      : await this.prisma.assessmentAttempt.findFirst({
          where: { assessmentId, studentId: profile.id, status: 'SUBMITTED' },
          orderBy: { completedAt: 'desc' },
        });

    if (!attempt) {
      throw new NotFoundException(
        attemptId
          ? 'Attempt tidak ditemukan.'
          : 'Belum ada attempt yang disubmit untuk assessment ini.',
      );
    }
    if (attempt.studentId !== profile.id) {
      throw new ForbiddenException('Attempt ini bukan milik kamu.');
    }
    if (attempt.assessmentId !== assessmentId) {
      throw new BadRequestException('Attempt ini bukan untuk assessment ini.');
    }
    if (attempt.status !== 'SUBMITTED') {
      throw new BadRequestException(
        'Attempt ini belum disubmit, belum ada hasil.',
      );
    }

    const answers = await this.prisma.assessmentAnswer.findMany({
      where: { attemptId: attempt.id },
      include: {
        question: {
          select: {
            id: true,
            questionText: true,
            difficulty: true,
            competencyId: true,
          },
        },
      },
    });

    // Snapshot mastery yang di-trigger OLEH attempt spesifik ini --
    // append-only, jadi ini rekonstruksi akurat dari competencyResults
    // yang dulu cuma sempat dikembalikan sekali di response submit().
    const competencySnapshots = await this.prisma.competencySnapshot.findMany({
      where: { triggeredByAttemptId: attempt.id, sourceType: 'ASSESSMENT' },
    });

    return { attempt, answers, competencySnapshots };
  }

  // Gap Phase 4 (19 Agustus 2026): sebelum ini TIDAK ADA endpoint untuk
  // membuat Assessment baru -- satu-satunya cara cuma lewat seed/fixture
  // manual. TEACHER-only karena Assessment.teacherId wajib diisi di
  // schema (assessment selalu punya pemilik teacher yang jelas).
  async createAssessment(userId: number, dto: CreateAssessmentDto) {
    const profile = await this.prisma.teacherProfile.findUnique({ where: { userId } });
    if (!profile) {
      throw new NotFoundException('Profil teacher tidak ditemukan.');
    }

    const subject = await this.prisma.subject.findUnique({ where: { id: dto.subjectId } });
    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    const questionIds = dto.questions.map((q) => q.questionId);
    const uniqueQuestionIds = [...new Set(questionIds)];
    if (uniqueQuestionIds.length !== questionIds.length) {
      throw new BadRequestException('Ada questionId yang dikirim berulang.');
    }

    const questions = await this.prisma.question.findMany({
      where: { id: { in: uniqueQuestionIds } },
    });
    if (questions.length !== uniqueQuestionIds.length) {
      throw new BadRequestException('Ada questionId yang tidak valid/tidak ditemukan.');
    }

    return this.prisma.assessment.create({
      data: {
        subjectId: dto.subjectId,
        teacherId: profile.id,
        title: dto.title,
        type: dto.type ?? 'FORMATIVE',
        durationMinutes: dto.durationMinutes,
        cooldownHours: dto.cooldownHours,
        questions: {
          create: dto.questions.map((q, index) => ({
            questionId: q.questionId,
            sequence: index,
            points: q.points ?? 1,
          })),
        },
      },
      include: { questions: true },
    });
  }
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/assessments/assessments.controller.ts")"
echo ">> Menulis src/assessments/assessments.controller.ts"
cat > src/assessments/assessments.controller.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
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
import { CreateAssessmentDto } from './dto/create-assessment.dto';

@Controller('assessments')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class AssessmentsController {
  constructor(private assessmentsService: AssessmentsService) {}

  // Gap Phase 4: sebelumnya tidak ada cara sama sekali bikin assessment
  // baru selain seed/fixture manual. TEACHER-only, cuma boleh assessment
  // milik sendiri -- lihat komentar service.
  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateAssessmentDto) {
    const assessment = await this.assessmentsService.createAssessment(user.userId, dto);
    return { success: true, data: assessment, message: 'Assessment berhasil dibuat' };
  }

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
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/assessments/dto/create-assessment.dto.ts")"
echo ">> Menulis src/assessments/dto/create-assessment.dto.ts"
cat > src/assessments/dto/create-assessment.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { CreateAssessmentQuestionDto } from './create-assessment-question.dto';

export class CreateAssessmentDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  title!: string;

  @IsOptional()
  @IsIn(['FORMATIVE', 'SUMMATIVE'])
  type?: string;

  @IsOptional()
  @IsInt()
  durationMinutes?: number;

  @IsOptional()
  @IsInt()
  cooldownHours?: number;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateAssessmentQuestionDto)
  questions!: CreateAssessmentQuestionDto[];
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/assessments/dto/create-assessment-question.dto.ts")"
echo ">> Menulis src/assessments/dto/create-assessment-question.dto.ts"
cat > src/assessments/dto/create-assessment-question.dto.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { IsInt, IsOptional, IsNumber, Min } from 'class-validator';

export class CreateAssessmentQuestionDto {
  @IsInt()
  questionId!: number;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  points?: number;
}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

mkdir -p "$(dirname "src/app.module.ts")"
echo ">> Menulis src/app.module.ts"
cat > src/app.module.ts << 'KELASXTRA_PHASE4_GAPCLOSE_19AUG2026'
import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './users/users.module';
import { AuthModule } from './auth/auth.module';
import { StudentsModule } from './students/students.module';
import { TeachersModule } from './teachers/teachers.module';
import { SubjectsModule } from './subjects/subjects.module';
import { TopicsModule } from './topics/topics.module';
import { CompetenciesModule } from './competencies/competencies.module';
import { CommonModule } from './common/common.module';
import { DiagnosticsModule } from './diagnostics/diagnostics.module';
import { AssessmentsModule } from './assessments/assessments.module';
import { QuestionBanksModule } from './question-banks/question-banks.module';
import { QuestionsModule } from './questions/questions.module';
import { CoursesModule } from './courses/courses.module';
import { LessonsModule } from './lessons/lessons.module';
import { MaterialsModule } from './materials/materials.module';
import { AdminModule } from './admin/admin.module';

@Module({
  imports: [
    // Rate limit default: 100 request/menit per IP (section 14 dokumen
    // master: "Endpoint sensitif harus memiliki validation dan rate
    // limiting"). Endpoint yang lebih sensitif (register/login) sudah
    // punya limit lebih ketat lewat @Throttle({...}) di AuthController —
    // tapi decorator itu baru benar-benar berlaku setelah ThrottlerGuard
    // didaftarkan sebagai APP_GUARD global di bawah.
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 100,
      },
    ]),
    CommonModule,
    PrismaModule,
    UsersModule,
    AuthModule,
    StudentsModule,
    TeachersModule,
    SubjectsModule,
    TopicsModule,
    CompetenciesModule,
    DiagnosticsModule,
    AssessmentsModule,
    QuestionBanksModule,
    QuestionsModule,
    CoursesModule,
    LessonsModule,
    MaterialsModule,
    AdminModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    // Rate limiting dimatikan HANYA saat NODE_ENV=test -- limit produksi
    // (termasuk @Throttle 5/60s di AuthController) sama sekali tidak
    // berubah untuk environment lain. Tanpa ini, e2e test yang bikin
    // banyak akun (happy path, duplicate submission, security, dst dalam
    // satu run) akan kena 429 padahal bukan itu yang sedang diuji.
    ...(process.env.NODE_ENV === 'test'
      ? []
      : [
          {
            provide: APP_GUARD,
            useClass: ThrottlerGuard,
          },
        ]),
  ],
})
export class AppModule {}
KELASXTRA_PHASE4_GAPCLOSE_19AUG2026

echo ""
echo ">> Semua file berhasil ditulis."
echo ""
echo "Tidak ada perubahan schema -- semua model (Course/Lesson/LearningMaterial/QuestionBank/Question/QuestionOption) sudah ada dari Phase 0-1, tidak perlu migration baru."
echo "Langkah selanjutnya:"
echo "1. npm run test:e2e   # pastikan tidak ada regresi ke fitur lama"
echo "2. npm run start:dev  # coba jalan, lalu tes endpoint baru manual (lihat daftar di bawah)"
echo ""
echo "Endpoint BARU yang bisa langsung dicoba:"
echo "  GET  /api/v1/students/me/competencies"
echo "  GET  /api/v1/students/me/learning-path"
echo "  GET  /api/v1/students/me/progress"
echo "  POST /api/v1/question-banks          (ADMIN/TEACHER)"
echo "  POST /api/v1/questions               (ADMIN/TEACHER)"
echo "  POST /api/v1/courses                 (TEACHER)"
echo "  POST /api/v1/lessons                 (TEACHER)"
echo "  POST /api/v1/materials                (TEACHER)"
echo "  POST /api/v1/diagnostics             (ADMIN) -- assembling questionIds jadi diagnostic test baru"
echo "  POST /api/v1/assessments             (TEACHER) -- assembling questions jadi assessment baru"
echo "  GET  /api/v1/admin/users             (ADMIN)"
echo "  PUT  /api/v1/admin/users/:id/status  (ADMIN) -- melengkapi enforcement SUSPENDED/DEACTIVATED yang sudah ada"
