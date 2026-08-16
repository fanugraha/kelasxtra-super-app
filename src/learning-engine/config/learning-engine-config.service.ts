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

  async getActiveConfig(
    tx?: Prisma.TransactionClient,
  ): Promise<LearningEngineConfigValues> {
    const client = tx ?? this.prisma;

    // Sengaja pakai findMany + cek count, BUKAN findFirst -- findFirst akan
    // diam-diam memilih satu baris kalau somehow ada >1 row active=true
    // (mis. human error saat tuning config manual), padahal itu artinya ada
    // ambiguitas config yang dipakai sistem tanpa siapa pun sadar (temuan
    // QA audit 16 Agustus 2026, item #7). MySQL tidak punya partial unique
    // index untuk enforce "cuma 1 row active" di level DB, jadi ini jadi
    // pengaman utama di level aplikasi.
    const activeConfigs = await client.learningEngineConfig.findMany({
      where: { active: true },
    });

    if (activeConfigs.length === 0) {
      throw new InternalServerErrorException(
        'Tidak ada LearningEngineConfig yang active=true. Jalankan seed atau aktifkan salah satu baris config.',
      );
    }

    if (activeConfigs.length > 1) {
      throw new InternalServerErrorException(
        `Ada ${activeConfigs.length} baris LearningEngineConfig dengan active=true (id: ${activeConfigs
          .map((c) => c.id)
          .join(
            ', ',
          )}). Harus tepat satu -- perbaiki data sebelum melanjutkan.`,
      );
    }

    const config = activeConfigs[0];

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
