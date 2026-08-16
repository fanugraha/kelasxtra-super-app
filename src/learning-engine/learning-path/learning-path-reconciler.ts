import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { MasteryBucket } from '../learning-engine.types';

export interface ReconcileInput {
  studentId: number;
  competencyId: number;
  oldBucket: MasteryBucket;
  newBucket: MasteryBucket;
}

/**
 * "Incremental Learning Path Reconciliation" (spec Phase 4 bagian 11):
 * TIDAK PERNAH regenerate seluruh learning path. Cuma bereaksi kalau bucket
 * competency berubah, dan cuma menyentuh item yang terkait competency itu
 * saja — bukan seluruh path milik siswa.
 *
 * V1 rule-based, sederhana:
 *   -> LEARNING_GAP : pastikan ada LearningPathItem PENDING untuk competency ini
 *   -> MASTERED      : tandai item terkait competency ini jadi DONE
 *   DEVELOPING / INSUFFICIENT_DATA belum ada aksi spesifik di V1.
 */
@Injectable()
export class LearningPathReconciler {
  async reconcile(tx: Prisma.TransactionClient, input: ReconcileInput): Promise<void> {
    const { studentId, competencyId, oldBucket, newBucket } = input;

    if (oldBucket === newBucket) {
      return; // bucket tidak berubah -> tidak ada yang perlu direkonsiliasi
    }

    if (newBucket === 'LEARNING_GAP') {
      await this.ensureItemExists(tx, studentId, competencyId);
      return;
    }

    if (newBucket === 'MASTERED') {
      await this.markItemsDone(tx, studentId, competencyId);
    }
  }

  private async getOrCreateActivePath(tx: Prisma.TransactionClient, studentId: number) {
    const existing = await tx.learningPath.findFirst({
      where: { studentId, status: 'ACTIVE' },
      orderBy: { generatedAt: 'desc' },
    });

    if (existing) {
      return existing;
    }

    return tx.learningPath.create({
      data: { studentId, title: 'Rencana Belajar', status: 'ACTIVE' },
    });
  }

  private async ensureItemExists(
    tx: Prisma.TransactionClient,
    studentId: number,
    competencyId: number,
  ) {
    const path = await this.getOrCreateActivePath(tx, studentId);

    const existingItem = await tx.learningPathItem.findFirst({
      where: { learningPathId: path.id, competencyId },
    });

    if (existingItem) {
      if (existingItem.status === 'DONE') {
        // Sempat dianggap selesai, sekarang gap lagi -> aktifkan ulang.
        await tx.learningPathItem.update({
          where: { id: existingItem.id },
          data: { status: 'PENDING' },
        });
      }
      return;
    }

    const maxSequence = await tx.learningPathItem.aggregate({
      where: { learningPathId: path.id },
      _max: { sequence: true },
    });

    await tx.learningPathItem.create({
      data: {
        learningPathId: path.id,
        competencyId,
        sequence: (maxSequence._max.sequence ?? 0) + 1,
        status: 'PENDING',
      },
    });
  }

  private async markItemsDone(
    tx: Prisma.TransactionClient,
    studentId: number,
    competencyId: number,
  ) {
    const path = await tx.learningPath.findFirst({
      where: { studentId, status: 'ACTIVE' },
    });

    if (!path) {
      return; // belum ada path sama sekali -> tidak ada yang perlu ditandai selesai
    }

    await tx.learningPathItem.updateMany({
      where: { learningPathId: path.id, competencyId, status: { not: 'DONE' } },
      data: { status: 'DONE' },
    });
  }
}
