-- Keputusan bisnis: diagnostic test dibatasi 1x per siswa per test.
-- Kolom void* dipakai ADMIN/TEACHER untuk "reset" attempt lama supaya
-- siswa bisa mengulang, tanpa menghapus riwayat attempt yang asli.
ALTER TABLE `diagnostic_attempts` ADD COLUMN `voidedAt` DATETIME(3) NULL;
ALTER TABLE `diagnostic_attempts` ADD COLUMN `voidReason` TEXT NULL;
ALTER TABLE `diagnostic_attempts` ADD COLUMN `voidedByUserId` INTEGER NULL;

CREATE INDEX `diagnostic_attempts_voidedByUserId_idx` ON `diagnostic_attempts`(`voidedByUserId`);

ALTER TABLE `diagnostic_attempts` ADD CONSTRAINT `diagnostic_attempts_voidedByUserId_fkey` FOREIGN KEY (`voidedByUserId`) REFERENCES `users`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
