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
