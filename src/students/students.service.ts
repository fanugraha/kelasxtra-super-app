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
