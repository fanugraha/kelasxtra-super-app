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
