import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTopicDto } from './dto/create-topic.dto';
import { UpdateTopicDto } from './dto/update-topic.dto';
import { ListTopicsDto } from './dto/list-topics.dto';

@Injectable()
export class TopicsService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListTopicsDto) {
    return await this.prisma.topic.findMany({
      where: { subjectId: query.subjectId },
      orderBy: [{ subjectId: 'asc' }, { sequence: 'asc' }],
    });
  }

  async findOne(id: number) {
    const topic = await this.prisma.topic.findUnique({ where: { id } });

    if (!topic) {
      throw new NotFoundException('Topic tidak ditemukan.');
    }

    return topic;
  }

  private async ensureSubjectExists(subjectId: number) {
    const subject = await this.prisma.subject.findUnique({
      where: { id: subjectId },
    });
    if (!subject) {
      throw new NotFoundException('Subject untuk topic ini tidak ditemukan.');
    }
  }

  async create(dto: CreateTopicDto) {
    await this.ensureSubjectExists(dto.subjectId);

    return this.prisma.topic.create({
      data: {
        subjectId: dto.subjectId,
        name: dto.name,
        sequence: dto.sequence ?? 0,
      },
    });
  }

  async update(id: number, dto: UpdateTopicDto) {
    await this.findOne(id);

    return this.prisma.topic.update({
      where: { id },
      data: dto,
    });
  }
}
