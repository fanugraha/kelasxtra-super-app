/*
  Warnings:

  - You are about to alter the column `confidenceScore` on the `student_competencies` table. The data in that column could be lost. The data in that column will be cast from `Decimal(5,2)` to `Decimal(5,4)`.

*/
-- AlterTable
ALTER TABLE `assessment_attempts` ADD COLUMN `flagReason` TEXT NULL,
    ADD COLUMN `flaggedAt` DATETIME(3) NULL,
    ADD COLUMN `isFlagged` BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE `diagnostic_attempts` ADD COLUMN `flagReason` TEXT NULL,
    ADD COLUMN `flaggedAt` DATETIME(3) NULL,
    ADD COLUMN `isFlagged` BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE `student_competencies` ADD COLUMN `lastAttemptAt` DATETIME(3) NULL,
    ADD COLUMN `masteryBucket` VARCHAR(191) NOT NULL DEFAULT 'INSUFFICIENT_DATA',
    ADD COLUMN `totalAnswered` INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN `totalCorrect` INTEGER NOT NULL DEFAULT 0,
    MODIFY `confidenceScore` DECIMAL(5, 4) NULL;

-- CreateTable
CREATE TABLE `competency_snapshots` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `studentId` INTEGER NOT NULL,
    `competencyId` INTEGER NOT NULL,
    `masteryScore` DECIMAL(5, 2) NOT NULL,
    `confidenceScore` DECIMAL(5, 4) NOT NULL,
    `totalAnswered` INTEGER NOT NULL,
    `totalCorrect` INTEGER NOT NULL,
    `masteryBucket` VARCHAR(191) NOT NULL,
    `triggeredByAttemptId` INTEGER NOT NULL,
    `sourceType` VARCHAR(191) NOT NULL,
    `engineVersion` INTEGER NOT NULL,
    `configVersion` INTEGER NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `competency_snapshots_studentId_competencyId_createdAt_idx`(`studentId`, `competencyId`, `createdAt`),
    INDEX `competency_snapshots_triggeredByAttemptId_idx`(`triggeredByAttemptId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `learning_engine_configs` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `alpha` DECIMAL(3, 2) NOT NULL DEFAULT 0.30,
    `difficultyEasyWeight` DECIMAL(3, 2) NOT NULL DEFAULT 1.0,
    `difficultyMediumWeight` DECIMAL(3, 2) NOT NULL DEFAULT 1.5,
    `difficultyHardWeight` DECIMAL(3, 2) NOT NULL DEFAULT 2.0,
    `masteredThreshold` DECIMAL(5, 2) NOT NULL DEFAULT 80,
    `developingThreshold` DECIMAL(5, 2) NOT NULL DEFAULT 60,
    `confidenceK` DECIMAL(5, 2) NOT NULL DEFAULT 5,
    `minimumConfidence` DECIMAL(3, 2) NOT NULL DEFAULT 0.60,
    `engineVersion` INTEGER NOT NULL DEFAULT 1,
    `configVersion` INTEGER NOT NULL DEFAULT 1,
    `active` BOOLEAN NOT NULL DEFAULT true,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateIndex
CREATE INDEX `student_competencies_studentId_masteryBucket_idx` ON `student_competencies`(`studentId`, `masteryBucket`);

-- AddForeignKey
ALTER TABLE `competency_snapshots` ADD CONSTRAINT `competency_snapshots_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `competency_snapshots` ADD CONSTRAINT `competency_snapshots_competencyId_fkey` FOREIGN KEY (`competencyId`) REFERENCES `competencies`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
