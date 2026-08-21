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
