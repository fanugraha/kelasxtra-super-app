-- AlterTable: teacher name (fixes silent data loss on TEACHER registration)
ALTER TABLE `teachers` ADD COLUMN `name` VARCHAR(191) NOT NULL DEFAULT '';
ALTER TABLE `teachers` ALTER COLUMN `name` DROP DEFAULT;

-- AlterTable: account lockout tracking
ALTER TABLE `users` ADD COLUMN `failedLoginAttempts` INTEGER NOT NULL DEFAULT 0;
ALTER TABLE `users` ADD COLUMN `lockedUntil` DATETIME(3) NULL;

-- CreateTable: audit log
CREATE TABLE `audit_logs` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `userId` INTEGER NULL,
    `action` VARCHAR(191) NOT NULL,
    `metadata` TEXT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `audit_logs_userId_idx`(`userId`),
    INDEX `audit_logs_action_idx`(`action`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `audit_logs` ADD CONSTRAINT `audit_logs_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
