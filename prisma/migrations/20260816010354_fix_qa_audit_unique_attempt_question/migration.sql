/*
  Warnings:

  - A unique constraint covering the columns `[attemptId,questionId]` on the table `assessment_answers` will be added. If there are existing duplicate values, this will fail.
  - A unique constraint covering the columns `[attemptId,questionId]` on the table `diagnostic_answers` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateIndex
CREATE UNIQUE INDEX `assessment_answers_attemptId_questionId_key` ON `assessment_answers`(`attemptId`, `questionId`);

-- CreateIndex
CREATE UNIQUE INDEX `diagnostic_answers_attemptId_questionId_key` ON `diagnostic_answers`(`attemptId`, `questionId`);
