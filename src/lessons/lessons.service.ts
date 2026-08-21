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
