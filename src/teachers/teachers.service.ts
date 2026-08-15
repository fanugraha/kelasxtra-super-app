import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateTeacherProfileDto } from './dto/update-profile.dto';

@Injectable()
export class TeachersService {
  constructor(private prisma: PrismaService) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.teacherProfile.findUnique({
      where: { userId },
    });

    if (!profile) {
      throw new NotFoundException('Profil teacher tidak ditemukan.');
    }

    return profile;
  }

  async getMyProfile(userId: number) {
    return this.findProfileByUserId(userId);
  }

  async updateMyProfile(userId: number, dto: UpdateTeacherProfileDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.teacherProfile.update({
      where: { id: profile.id },
      data: dto,
    });
  }
}
