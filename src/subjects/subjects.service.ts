import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateSubjectDto } from './dto/create-subject.dto';
import { UpdateSubjectDto } from './dto/update-subject.dto';
import { ListSubjectsDto } from './dto/list-subjects.dto';

@Injectable()
export class SubjectsService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListSubjectsDto) {
    return await this.prisma.subject.findMany({
      where: {
        status: query.includeInactive === 'true' ? undefined : 'ACTIVE',
        gradeLevel: query.gradeLevel,
      },
      orderBy: { name: 'asc' },
    });
  }

  async findOne(id: number) {
    const subject = await this.prisma.subject.findUnique({
      where: { id },
      include: { topics: { orderBy: { sequence: 'asc' } } },
    });

    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    return subject;
  }

  async create(dto: CreateSubjectDto) {
    const existing = await this.prisma.subject.findUnique({
      where: { code: dto.code },
    });
    if (existing) {
      throw new ConflictException('Kode subject sudah digunakan.');
    }

    return this.prisma.subject.create({
      data: {
        code: dto.code,
        name: dto.name,
        gradeLevel: dto.gradeLevel,
        status: dto.status ?? 'ACTIVE',
      },
    });
  }

  async update(id: number, dto: UpdateSubjectDto) {
    await this.findOne(id);

    if (dto.code) {
      const existing = await this.prisma.subject.findUnique({
        where: { code: dto.code },
      });
      if (existing && existing.id !== id) {
        throw new ConflictException('Kode subject sudah digunakan.');
      }
    }

    return this.prisma.subject.update({
      where: { id },
      data: dto,
    });
  }
}
