/*
  Warnings:

  - A unique constraint covering the columns `[studentCode]` on the table `student_profiles` will be added. If there are existing duplicate values, this will fail.

*/
-- AlterTable
ALTER TABLE `student_profiles` ADD COLUMN `studentCode` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `users` ADD COLUMN `status` VARCHAR(191) NOT NULL DEFAULT 'ACTIVE';

-- CreateTable
CREATE TABLE `student_goals` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `studentId` INTEGER NOT NULL,
    `goalType` VARCHAR(191) NOT NULL,
    `targetValue` VARCHAR(191) NULL,
    `targetDate` DATETIME(3) NULL,
    `priority` INTEGER NOT NULL DEFAULT 0,
    `status` VARCHAR(191) NOT NULL DEFAULT 'ACTIVE',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `student_goals_studentId_idx`(`studentId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `student_preferences` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `studentId` INTEGER NOT NULL,
    `language` VARCHAR(191) NOT NULL DEFAULT 'id',
    `learningPreferences` TEXT NULL,
    `dailyTargetMinutes` INTEGER NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `student_preferences_studentId_key`(`studentId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `student_competencies` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `studentId` INTEGER NOT NULL,
    `competencyId` INTEGER NOT NULL,
    `masteryScore` DECIMAL(5, 2) NOT NULL DEFAULT 0,
    `confidenceScore` DECIMAL(5, 2) NULL,
    `updatedAt` DATETIME(3) NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `student_competencies_competencyId_idx`(`competencyId`),
    UNIQUE INDEX `student_competencies_studentId_competencyId_key`(`studentId`, `competencyId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `teachers` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `userId` INTEGER NOT NULL,
    `teacherCode` VARCHAR(191) NULL,
    `bio` TEXT NULL,
    `education` VARCHAR(191) NULL,
    `experienceYears` INTEGER NULL,
    `verificationStatus` VARCHAR(191) NOT NULL DEFAULT 'PENDING',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `teachers_userId_key`(`userId`),
    UNIQUE INDEX `teachers_teacherCode_key`(`teacherCode`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `teacher_skills` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `teacherId` INTEGER NOT NULL,
    `competencyId` INTEGER NOT NULL,
    `proficiencyLevel` VARCHAR(191) NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `teacher_skills_competencyId_idx`(`competencyId`),
    UNIQUE INDEX `teacher_skills_teacherId_competencyId_key`(`teacherId`, `competencyId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `teacher_certifications` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `teacherId` INTEGER NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `issuer` VARCHAR(191) NULL,
    `issuedAt` DATETIME(3) NULL,
    `verificationStatus` VARCHAR(191) NOT NULL DEFAULT 'PENDING',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `teacher_certifications_teacherId_idx`(`teacherId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `subjects` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `code` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `gradeLevel` VARCHAR(191) NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'ACTIVE',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `subjects_code_key`(`code`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `topics` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `subjectId` INTEGER NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `sequence` INTEGER NOT NULL DEFAULT 0,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `topics_subjectId_idx`(`subjectId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `competencies` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `subjectId` INTEGER NOT NULL,
    `topicId` INTEGER NULL,
    `code` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `gradeLevel` VARCHAR(191) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `competencies_code_key`(`code`),
    INDEX `competencies_subjectId_idx`(`subjectId`),
    INDEX `competencies_topicId_idx`(`topicId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `courses` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `subjectId` INTEGER NOT NULL,
    `teacherId` INTEGER NOT NULL,
    `title` VARCHAR(191) NOT NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'DRAFT',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `courses_subjectId_idx`(`subjectId`),
    INDEX `courses_teacherId_idx`(`teacherId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `lessons` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `courseId` INTEGER NOT NULL,
    `topicId` INTEGER NULL,
    `title` VARCHAR(191) NOT NULL,
    `sequence` INTEGER NOT NULL DEFAULT 0,
    `status` VARCHAR(191) NOT NULL DEFAULT 'DRAFT',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `lessons_courseId_idx`(`courseId`),
    INDEX `lessons_topicId_idx`(`topicId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `learning_materials` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `lessonId` INTEGER NOT NULL,
    `title` VARCHAR(191) NOT NULL,
    `type` VARCHAR(191) NOT NULL,
    `content` TEXT NULL,
    `resourceUrl` VARCHAR(191) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `learning_materials_lessonId_idx`(`lessonId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `question_banks` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `subjectId` INTEGER NOT NULL,
    `topicId` INTEGER NULL,
    `competencyId` INTEGER NULL,
    `teacherId` INTEGER NULL,
    `name` VARCHAR(191) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `question_banks_subjectId_idx`(`subjectId`),
    INDEX `question_banks_topicId_idx`(`topicId`),
    INDEX `question_banks_competencyId_idx`(`competencyId`),
    INDEX `question_banks_teacherId_idx`(`teacherId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `questions` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `questionBankId` INTEGER NOT NULL,
    `competencyId` INTEGER NULL,
    `questionText` TEXT NOT NULL,
    `questionType` VARCHAR(191) NOT NULL DEFAULT 'MULTIPLE_CHOICE',
    `difficulty` VARCHAR(191) NOT NULL DEFAULT 'MEDIUM',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `questions_questionBankId_idx`(`questionBankId`),
    INDEX `questions_competencyId_idx`(`competencyId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `question_options` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `questionId` INTEGER NOT NULL,
    `optionText` TEXT NOT NULL,
    `isCorrect` BOOLEAN NOT NULL DEFAULT false,
    `sequence` INTEGER NOT NULL DEFAULT 0,

    INDEX `question_options_questionId_idx`(`questionId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `diagnostic_tests` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `subjectId` INTEGER NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `durationMinutes` INTEGER NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'ACTIVE',
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `diagnostic_tests_subjectId_idx`(`subjectId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `diagnostic_questions` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `diagnosticTestId` INTEGER NOT NULL,
    `questionId` INTEGER NOT NULL,
    `sequence` INTEGER NOT NULL DEFAULT 0,

    INDEX `diagnostic_questions_questionId_idx`(`questionId`),
    UNIQUE INDEX `diagnostic_questions_diagnosticTestId_questionId_key`(`diagnosticTestId`, `questionId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `diagnostic_attempts` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `diagnosticTestId` INTEGER NOT NULL,
    `studentId` INTEGER NOT NULL,
    `attemptNumber` INTEGER NOT NULL DEFAULT 1,
    `score` DECIMAL(5, 2) NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'IN_PROGRESS',
    `startedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `completedAt` DATETIME(3) NULL,

    INDEX `diagnostic_attempts_diagnosticTestId_idx`(`diagnosticTestId`),
    INDEX `diagnostic_attempts_studentId_idx`(`studentId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `diagnostic_answers` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `attemptId` INTEGER NOT NULL,
    `questionId` INTEGER NOT NULL,
    `selectedOptionId` INTEGER NULL,
    `isCorrect` BOOLEAN NULL,
    `timeSpentSeconds` INTEGER NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `diagnostic_answers_attemptId_idx`(`attemptId`),
    INDEX `diagnostic_answers_questionId_idx`(`questionId`),
    INDEX `diagnostic_answers_selectedOptionId_idx`(`selectedOptionId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `learning_paths` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `studentId` INTEGER NOT NULL,
    `goalId` INTEGER NULL,
    `title` VARCHAR(191) NOT NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'ACTIVE',
    `generatedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `learning_paths_studentId_idx`(`studentId`),
    INDEX `learning_paths_goalId_idx`(`goalId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `learning_path_items` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `learningPathId` INTEGER NOT NULL,
    `lessonId` INTEGER NULL,
    `competencyId` INTEGER NULL,
    `sequence` INTEGER NOT NULL DEFAULT 0,
    `status` VARCHAR(191) NOT NULL DEFAULT 'PENDING',

    INDEX `learning_path_items_learningPathId_idx`(`learningPathId`),
    INDEX `learning_path_items_lessonId_idx`(`lessonId`),
    INDEX `learning_path_items_competencyId_idx`(`competencyId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `student_progress` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `studentId` INTEGER NOT NULL,
    `lessonId` INTEGER NOT NULL,
    `progressPercentage` DECIMAL(5, 2) NOT NULL DEFAULT 0,
    `status` VARCHAR(191) NOT NULL DEFAULT 'NOT_STARTED',
    `startedAt` DATETIME(3) NULL,
    `completedAt` DATETIME(3) NULL,
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `student_progress_lessonId_idx`(`lessonId`),
    UNIQUE INDEX `student_progress_studentId_lessonId_key`(`studentId`, `lessonId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `assessments` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `subjectId` INTEGER NOT NULL,
    `teacherId` INTEGER NOT NULL,
    `title` VARCHAR(191) NOT NULL,
    `type` VARCHAR(191) NOT NULL DEFAULT 'FORMATIVE',
    `durationMinutes` INTEGER NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `assessments_subjectId_idx`(`subjectId`),
    INDEX `assessments_teacherId_idx`(`teacherId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `assessment_questions` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `assessmentId` INTEGER NOT NULL,
    `questionId` INTEGER NOT NULL,
    `sequence` INTEGER NOT NULL DEFAULT 0,
    `points` DECIMAL(5, 2) NOT NULL DEFAULT 1,

    INDEX `assessment_questions_questionId_idx`(`questionId`),
    UNIQUE INDEX `assessment_questions_assessmentId_questionId_key`(`assessmentId`, `questionId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `assessment_attempts` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `assessmentId` INTEGER NOT NULL,
    `studentId` INTEGER NOT NULL,
    `attemptNumber` INTEGER NOT NULL DEFAULT 1,
    `score` DECIMAL(5, 2) NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'IN_PROGRESS',
    `startedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `completedAt` DATETIME(3) NULL,

    INDEX `assessment_attempts_assessmentId_idx`(`assessmentId`),
    INDEX `assessment_attempts_studentId_idx`(`studentId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `assessment_answers` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `attemptId` INTEGER NOT NULL,
    `questionId` INTEGER NOT NULL,
    `selectedOptionId` INTEGER NULL,
    `isCorrect` BOOLEAN NULL,
    `pointsEarned` DECIMAL(5, 2) NULL,
    `timeSpentSeconds` INTEGER NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `assessment_answers_attemptId_idx`(`attemptId`),
    INDEX `assessment_answers_questionId_idx`(`questionId`),
    INDEX `assessment_answers_selectedOptionId_idx`(`selectedOptionId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateIndex
CREATE UNIQUE INDEX `student_profiles_studentCode_key` ON `student_profiles`(`studentCode`);

-- AddForeignKey
ALTER TABLE `student_goals` ADD CONSTRAINT `student_goals_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `student_preferences` ADD CONSTRAINT `student_preferences_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `student_competencies` ADD CONSTRAINT `student_competencies_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `student_competencies` ADD CONSTRAINT `student_competencies_competencyId_fkey` FOREIGN KEY (`competencyId`) REFERENCES `competencies`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `teachers` ADD CONSTRAINT `teachers_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `teacher_skills` ADD CONSTRAINT `teacher_skills_teacherId_fkey` FOREIGN KEY (`teacherId`) REFERENCES `teachers`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `teacher_skills` ADD CONSTRAINT `teacher_skills_competencyId_fkey` FOREIGN KEY (`competencyId`) REFERENCES `competencies`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `teacher_certifications` ADD CONSTRAINT `teacher_certifications_teacherId_fkey` FOREIGN KEY (`teacherId`) REFERENCES `teachers`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `topics` ADD CONSTRAINT `topics_subjectId_fkey` FOREIGN KEY (`subjectId`) REFERENCES `subjects`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `competencies` ADD CONSTRAINT `competencies_subjectId_fkey` FOREIGN KEY (`subjectId`) REFERENCES `subjects`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `competencies` ADD CONSTRAINT `competencies_topicId_fkey` FOREIGN KEY (`topicId`) REFERENCES `topics`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `courses` ADD CONSTRAINT `courses_subjectId_fkey` FOREIGN KEY (`subjectId`) REFERENCES `subjects`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `courses` ADD CONSTRAINT `courses_teacherId_fkey` FOREIGN KEY (`teacherId`) REFERENCES `teachers`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `lessons` ADD CONSTRAINT `lessons_courseId_fkey` FOREIGN KEY (`courseId`) REFERENCES `courses`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `lessons` ADD CONSTRAINT `lessons_topicId_fkey` FOREIGN KEY (`topicId`) REFERENCES `topics`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `learning_materials` ADD CONSTRAINT `learning_materials_lessonId_fkey` FOREIGN KEY (`lessonId`) REFERENCES `lessons`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `question_banks` ADD CONSTRAINT `question_banks_subjectId_fkey` FOREIGN KEY (`subjectId`) REFERENCES `subjects`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `question_banks` ADD CONSTRAINT `question_banks_topicId_fkey` FOREIGN KEY (`topicId`) REFERENCES `topics`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `question_banks` ADD CONSTRAINT `question_banks_competencyId_fkey` FOREIGN KEY (`competencyId`) REFERENCES `competencies`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `question_banks` ADD CONSTRAINT `question_banks_teacherId_fkey` FOREIGN KEY (`teacherId`) REFERENCES `teachers`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `questions` ADD CONSTRAINT `questions_questionBankId_fkey` FOREIGN KEY (`questionBankId`) REFERENCES `question_banks`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `questions` ADD CONSTRAINT `questions_competencyId_fkey` FOREIGN KEY (`competencyId`) REFERENCES `competencies`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `question_options` ADD CONSTRAINT `question_options_questionId_fkey` FOREIGN KEY (`questionId`) REFERENCES `questions`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_tests` ADD CONSTRAINT `diagnostic_tests_subjectId_fkey` FOREIGN KEY (`subjectId`) REFERENCES `subjects`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_questions` ADD CONSTRAINT `diagnostic_questions_diagnosticTestId_fkey` FOREIGN KEY (`diagnosticTestId`) REFERENCES `diagnostic_tests`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_questions` ADD CONSTRAINT `diagnostic_questions_questionId_fkey` FOREIGN KEY (`questionId`) REFERENCES `questions`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_attempts` ADD CONSTRAINT `diagnostic_attempts_diagnosticTestId_fkey` FOREIGN KEY (`diagnosticTestId`) REFERENCES `diagnostic_tests`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_attempts` ADD CONSTRAINT `diagnostic_attempts_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_answers` ADD CONSTRAINT `diagnostic_answers_attemptId_fkey` FOREIGN KEY (`attemptId`) REFERENCES `diagnostic_attempts`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_answers` ADD CONSTRAINT `diagnostic_answers_questionId_fkey` FOREIGN KEY (`questionId`) REFERENCES `questions`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `diagnostic_answers` ADD CONSTRAINT `diagnostic_answers_selectedOptionId_fkey` FOREIGN KEY (`selectedOptionId`) REFERENCES `question_options`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `learning_paths` ADD CONSTRAINT `learning_paths_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `learning_paths` ADD CONSTRAINT `learning_paths_goalId_fkey` FOREIGN KEY (`goalId`) REFERENCES `student_goals`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `learning_path_items` ADD CONSTRAINT `learning_path_items_learningPathId_fkey` FOREIGN KEY (`learningPathId`) REFERENCES `learning_paths`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `learning_path_items` ADD CONSTRAINT `learning_path_items_lessonId_fkey` FOREIGN KEY (`lessonId`) REFERENCES `lessons`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `learning_path_items` ADD CONSTRAINT `learning_path_items_competencyId_fkey` FOREIGN KEY (`competencyId`) REFERENCES `competencies`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `student_progress` ADD CONSTRAINT `student_progress_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `student_progress` ADD CONSTRAINT `student_progress_lessonId_fkey` FOREIGN KEY (`lessonId`) REFERENCES `lessons`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessments` ADD CONSTRAINT `assessments_subjectId_fkey` FOREIGN KEY (`subjectId`) REFERENCES `subjects`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessments` ADD CONSTRAINT `assessments_teacherId_fkey` FOREIGN KEY (`teacherId`) REFERENCES `teachers`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_questions` ADD CONSTRAINT `assessment_questions_assessmentId_fkey` FOREIGN KEY (`assessmentId`) REFERENCES `assessments`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_questions` ADD CONSTRAINT `assessment_questions_questionId_fkey` FOREIGN KEY (`questionId`) REFERENCES `questions`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_attempts` ADD CONSTRAINT `assessment_attempts_assessmentId_fkey` FOREIGN KEY (`assessmentId`) REFERENCES `assessments`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_attempts` ADD CONSTRAINT `assessment_attempts_studentId_fkey` FOREIGN KEY (`studentId`) REFERENCES `student_profiles`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_answers` ADD CONSTRAINT `assessment_answers_attemptId_fkey` FOREIGN KEY (`attemptId`) REFERENCES `assessment_attempts`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_answers` ADD CONSTRAINT `assessment_answers_questionId_fkey` FOREIGN KEY (`questionId`) REFERENCES `questions`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `assessment_answers` ADD CONSTRAINT `assessment_answers_selectedOptionId_fkey` FOREIGN KEY (`selectedOptionId`) REFERENCES `question_options`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
