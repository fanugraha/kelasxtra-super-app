import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCompetencyDto } from './dto/create-competency.dto';
import { UpdateCompetencyDto } from './dto/update-competency.dto';
import { ListCompetenciesDto } from './dto/list-competencies.dto';

@Injectable()
export class CompetenciesService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListCompetenciesDto) {
    return await this.prisma.competency.findMany({
      where: {
        subjectId: query.subjectId,
        topicId: query.topicId,
      },
      orderBy: { code: 'asc' },
    });
  }

  async findOne(id: number) {
    const competency = await this.prisma.competency.findUnique({
      where: { id },
    });

    if (!competency) {
      throw new NotFoundException('Competency tidak ditemukan.');
    }

    return competency;
  }

  private async validateReferences(subjectId: number, topicId?: number) {
    const subject = await this.prisma.subject.findUnique({
      where: { id: subjectId },
    });
    if (!subject) {
      throw new NotFoundException(
        'Subject untuk competency ini tidak ditemukan.',
      );
    }

    if (topicId) {
      const topic = await this.prisma.topic.findUnique({
        where: { id: topicId },
      });
      if (!topic) {
        throw new NotFoundException(
          'Topic untuk competency ini tidak ditemukan.',
        );
      }
      // Topic harus benar-benar berada di bawah subject yang sama, biar konsisten.
      if (topic.subjectId !== subjectId) {
        throw new ConflictException(
          'Topic yang dipilih tidak berada di subject yang sama.',
        );
      }
    }
  }

  async create(dto: CreateCompetencyDto) {
    const existing = await this.prisma.competency.findUnique({
      where: { code: dto.code },
    });
    if (existing) {
      throw new ConflictException('Kode competency sudah digunakan.');
    }

    await this.validateReferences(dto.subjectId, dto.topicId);

    return this.prisma.competency.create({
      data: {
        subjectId: dto.subjectId,
        topicId: dto.topicId,
        code: dto.code,
        name: dto.name,
        gradeLevel: dto.gradeLevel,
      },
    });
  }

  async update(id: number, dto: UpdateCompetencyDto) {
    const competency = await this.findOne(id);

    if (dto.code) {
      const existing = await this.prisma.competency.findUnique({
        where: { code: dto.code },
      });
      if (existing && existing.id !== id) {
        throw new ConflictException('Kode competency sudah digunakan.');
      }
    }

    if (dto.topicId) {
      await this.validateReferences(competency.subjectId, dto.topicId);
    }

    return this.prisma.competency.update({
      where: { id },
      data: dto,
    });
  }
}
