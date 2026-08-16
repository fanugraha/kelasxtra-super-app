-- AlterTable
ALTER TABLE `assessments` ADD COLUMN `cooldownHours` INTEGER NULL;

-- AlterTable
ALTER TABLE `diagnostic_tests` ADD COLUMN `allowMultipleAttempts` BOOLEAN NOT NULL DEFAULT false;
