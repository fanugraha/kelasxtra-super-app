import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { Prisma } from '../../../generated/prisma/client';
import { LearningEngineConfigValues } from '../learning-engine.types';

/**
 * Satu-satunya tempat yang boleh membaca LearningEngineConfig. Sengaja
 * TIDAK fallback ke nilai hardcoded kalau tidak ada config yang active —
 * lebih baik gagal jelas saat dipakai daripada diam-diam pakai formula
 * yang salah (konsisten dengan prinsip PrismaService di project ini yang
 * juga tidak fallback diam-diam untuk DATABASE_URL).
 */
@Injectable()
export class LearningEngineConfigService {
  constructor(private prisma: PrismaService) {}

  async getActiveConfig(tx?: Prisma.TransactionClient): Promise<LearningEngineConfigValues> {
    const client = tx ?? this.prisma;

    const config = await client.learningEngineConfig.findFirst({
      where: { active: true },
    });

    if (!config) {
      throw new InternalServerErrorException(
        'Tidak ada LearningEngineConfig yang active=true. Jalankan seed atau aktifkan salah satu baris config.',
      );
    }

    return {
      alpha: Number(config.alpha),
      difficultyEasyWeight: Number(config.difficultyEasyWeight),
      difficultyMediumWeight: Number(config.difficultyMediumWeight),
      difficultyHardWeight: Number(config.difficultyHardWeight),
      masteredThreshold: Number(config.masteredThreshold),
      developingThreshold: Number(config.developingThreshold),
      confidenceK: Number(config.confidenceK),
      minimumConfidence: Number(config.minimumConfidence),
      engineVersion: config.engineVersion,
      configVersion: config.configVersion,
    };
  }
}
