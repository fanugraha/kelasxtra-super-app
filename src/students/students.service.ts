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
}