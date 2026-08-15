import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private prisma: PrismaService) {}

  async findUserByEmail(email: string) {
    return this.prisma.user.findUnique({
      where: { email },
      include: { role: true, studentProfile: true },
    });
  }

  async findUserById(userId: number) {
    return this.prisma.user.findUnique({
      where: { id: userId },
      include: { role: true, studentProfile: true },
    });
  }

  async createStudentUser(data: { email: string; hashedPassword: string; name: string }) {
    // Setiap user baru yang register otomatis jadi role STUDENT
    const studentRole = await this.prisma.role.findUnique({
      where: { name: 'STUDENT' },
    });

    if (!studentRole) {
      throw new Error('Role STUDENT belum ada di database. Jalankan seed role terlebih dahulu.');
    }

    return this.prisma.user.create({
      data: {
        email: data.email,
        password: data.hashedPassword,
        roleId: studentRole.id,
        studentProfile: {
          create: {
            name: data.name,
          },
        },
      },
      include: { role: true, studentProfile: true },
    });
  }
}