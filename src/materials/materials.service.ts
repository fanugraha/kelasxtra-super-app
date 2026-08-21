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
