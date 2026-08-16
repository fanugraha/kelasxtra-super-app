#!/usr/bin/env bash
# apply_qa_audit_fixes_16aug2026.sh
#
# KelasXtra backend -- perbaikan untuk temuan QA Audit Phase 4 (16 Agustus 2026):
#
#   CRITICAL:
#     Bug #1 -- cross-question answer key exploit (evidence-aggregator.ts, evidence.service.ts)
#     Bug #2 -- duplicate questionId dalam satu submission (diagnostics/assessments.service.ts + schema unique constraint)
#   HIGH:
#     #5 -- masteryBucket tidak pernah di-assert di e2e test -> ditambahkan
#   MEDIUM:
#     #7 -- LearningEngineConfigService diam-diam pilih 1 row kalau active>1 -> sekarang throw error eksplisit
#     #8 -- aggregateEvidence throw Error biasa -> sekarang BadRequestException
#     #10 -- RBAC negative test (role TEACHER vs endpoint STUDENT) -> ditambahkan utk diagnostics & assessments
#   LOW:
#     ArrayMaxSize(200) di kedua submit DTO (hardening payload raksasa)
#
# BELUM termasuk (butuh keputusan bisnis, lihat chat):
#   #3 (duration enforcement), #4 (attempt cap), #6 (true concurrent race test),
#   #9 (GET /assessments/:id/results endpoint), full e2e suite Assessment (happy path/rollback/performance)
#
# Idempotent -- aman dijalankan berkali-kali, akan overwrite file dengan versi terbaru.
# Jalankan dari ROOT folder project backend (kelasxtra-super-app).

set -e

if [ ! -f "package.json" ] || [ ! -d "prisma" ]; then
  echo "Jalankan script ini dari root folder backend (kelasxtra-super-app), bukan dari folder lain."
  exit 1
fi

echo ">> Menulis file yang diperbaiki..."
mkdir -p src/assessments/dto src/diagnostics/dto src/learning-engine/config src/learning-engine/evidence test/utils

echo ">> Menulis prisma/schema.prisma"
mkdir -p $(dirname prisma/schema.prisma)
cat > prisma/schema.prisma << 'FILEEOF'
// This is your Prisma schema file,
// learn more about it in the docs: https://pris.ly/d/prisma-schema
//
// Struktur ini mengikuti ERD konseptual & Database Table Specification
// pada KelasXtra Master Product & Technical Documentation (section 9 & 10).
// V1 scope only (STUDENT + TEACHER + ADMIN core learning engine).

generator client {
  provider     = "prisma-client"
  output       = "../generated/prisma"
  moduleFormat = "cjs"
}

datasource db {
  provider = "mysql"
}

// ============================================================
// 10.1 IDENTITY & ACCESS
// ============================================================

model Role {
  id   Int    @id @default(autoincrement())
  name String @unique // STUDENT, ADMIN, PARENT, TUTOR, PROFESSIONAL

  users User[]

  @@map("roles")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  password  String
  roleId    Int
  status    String   @default("ACTIVE") // ACTIVE, SUSPENDED, DEACTIVATED
  failedLoginAttempts Int       @default(0)
  lockedUntil         DateTime?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  role           Role            @relation(fields: [roleId], references: [id])
  studentProfile StudentProfile?
  teacherProfile TeacherProfile?
  refreshTokens  RefreshToken[]
  auditLogs      AuditLog[]

  @@index([roleId])
  @@map("users")
}

model RefreshToken {
  id        Int      @id @default(autoincrement())
  userId    Int
  tokenHash String   @unique
  revoked   Boolean  @default(false)
  expiresAt DateTime
  createdAt DateTime @default(now())

  user User @relation(fields: [userId], references: [id])

  @@index([userId])
  @@map("refresh_tokens")
}

model AuditLog {
  id        Int      @id @default(autoincrement())
  userId    Int?
  action    String // REGISTER, LOGIN_SUCCESS, LOGIN_FAILED, ACCOUNT_LOCKED, LOGOUT
  metadata  String?  @db.Text // JSON-encoded free-form context (email, ip, dst.)
  createdAt DateTime @default(now())

  user User? @relation(fields: [userId], references: [id])

  @@index([userId])
  @@index([action])
  @@map("audit_logs")
}

// ============================================================
// 10.2 STUDENT
// ============================================================

model StudentProfile {
  id             Int      @id @default(autoincrement())
  userId         Int      @unique
  studentCode    String?  @unique
  name           String
  school         String?
  grade          String? // grade_level
  graduationYear Int?
  phone          String?
  createdAt      DateTime @default(now())
  updatedAt      DateTime @updatedAt

  user         User                @relation(fields: [userId], references: [id])
  goals        StudentGoal[]
  preference   StudentPreference?
  competencies StudentCompetency[]
  diagnosticAttempts  DiagnosticAttempt[]
  assessmentAttempts  AssessmentAttempt[]
  progress     StudentProgress[]
  learningPaths LearningPath[]
  competencySnapshots CompetencySnapshot[]

  @@map("student_profiles")
}

model StudentGoal {
  id         Int       @id @default(autoincrement())
  studentId  Int
  goalType   String
  targetValue String?
  targetDate DateTime?
  priority   Int       @default(0)
  status     String    @default("ACTIVE") // ACTIVE, ACHIEVED, CANCELLED
  createdAt  DateTime  @default(now())
  updatedAt  DateTime  @updatedAt

  student       StudentProfile @relation(fields: [studentId], references: [id])
  learningPaths LearningPath[]

  @@index([studentId])
  @@map("student_goals")
}

model StudentPreference {
  id                  Int      @id @default(autoincrement())
  studentId           Int      @unique
  language            String   @default("id")
  learningPreferences String?  @db.Text // JSON-encoded free-form preferences
  dailyTargetMinutes  Int?
  createdAt           DateTime @default(now())
  updatedAt           DateTime @updatedAt

  student StudentProfile @relation(fields: [studentId], references: [id])

  @@map("student_preferences")
}

model StudentCompetency {
  id              Int       @id @default(autoincrement())
  studentId       Int
  competencyId    Int
  totalAnswered   Int       @default(0) // hanya bertambah, jangan pernah di-reset
  totalCorrect    Int       @default(0) // hanya bertambah, jangan pernah di-reset
  masteryScore    Decimal   @default(0) @db.Decimal(5, 2) // derived state, dihitung via EMA
  confidenceScore Decimal?  @db.Decimal(5, 4) // derived state, fungsi saturasi dari totalAnswered
  masteryBucket   String    @default("INSUFFICIENT_DATA") // INSUFFICIENT_DATA, LEARNING_GAP, DEVELOPING, MASTERED
  lastAttemptAt   DateTime?
  updatedAt       DateTime  @updatedAt
  createdAt       DateTime  @default(now())

  student    StudentProfile @relation(fields: [studentId], references: [id])
  competency Competency     @relation(fields: [competencyId], references: [id])

  @@unique([studentId, competencyId])
  @@index([competencyId])
  @@index([studentId, masteryBucket])
  @@map("student_competencies")
}

// ============================================================
// 10.3 TEACHER
// ============================================================

model TeacherProfile {
  id                 Int      @id @default(autoincrement())
  userId             Int      @unique
  teacherCode        String?  @unique
  name               String
  bio                String?  @db.Text
  education          String?
  experienceYears    Int?
  verificationStatus String   @default("PENDING") // PENDING, VERIFIED, REJECTED
  createdAt          DateTime @default(now())
  updatedAt          DateTime @updatedAt

  user            User                   @relation(fields: [userId], references: [id])
  skills          TeacherSkill[]
  certifications  TeacherCertification[]
  courses         Course[]
  questionBanks   QuestionBank[]
  assessments     Assessment[]

  @@map("teachers")
}

model TeacherSkill {
  id                Int      @id @default(autoincrement())
  teacherId         Int
  competencyId      Int
  proficiencyLevel  String // BASIC, INTERMEDIATE, ADVANCED, EXPERT
  createdAt         DateTime @default(now())

  teacher    TeacherProfile @relation(fields: [teacherId], references: [id])
  competency Competency     @relation(fields: [competencyId], references: [id])

  @@unique([teacherId, competencyId])
  @@index([competencyId])
  @@map("teacher_skills")
}

model TeacherCertification {
  id                 Int       @id @default(autoincrement())
  teacherId          Int
  name               String
  issuer             String?
  issuedAt           DateTime?
  verificationStatus String    @default("PENDING") // PENDING, VERIFIED, REJECTED
  createdAt          DateTime  @default(now())

  teacher TeacherProfile @relation(fields: [teacherId], references: [id])

  @@index([teacherId])
  @@map("teacher_certifications")
}

// ============================================================
// 10.4 ACADEMIC STRUCTURE
// ============================================================

model Subject {
  id         Int      @id @default(autoincrement())
  code       String   @unique
  name       String
  gradeLevel String?
  status     String   @default("ACTIVE") // ACTIVE, INACTIVE
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt

  topics         Topic[]
  competencies   Competency[]
  courses        Course[]
  questionBanks  QuestionBank[]
  diagnosticTests DiagnosticTest[]
  assessments    Assessment[]

  @@map("subjects")
}

model Topic {
  id        Int      @id @default(autoincrement())
  subjectId Int
  name      String
  sequence  Int      @default(0)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  subject      Subject      @relation(fields: [subjectId], references: [id])
  competencies Competency[]
  lessons      Lesson[]
  questionBanks QuestionBank[]

  @@index([subjectId])
  @@map("topics")
}

model Competency {
  id         Int      @id @default(autoincrement())
  subjectId  Int
  topicId    Int?
  code       String   @unique
  name       String
  gradeLevel String?
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt

  subject             Subject               @relation(fields: [subjectId], references: [id])
  topic                Topic?               @relation(fields: [topicId], references: [id])
  studentCompetencies  StudentCompetency[]
  teacherSkills        TeacherSkill[]
  questions            Question[]
  questionBanks        QuestionBank[]
  learningPathItems    LearningPathItem[]
  competencySnapshots  CompetencySnapshot[]

  @@index([subjectId])
  @@index([topicId])
  @@map("competencies")
}

// ============================================================
// 10.5 CONTENT
// ============================================================

model Course {
  id        Int      @id @default(autoincrement())
  subjectId Int
  teacherId Int
  title     String
  status    String   @default("DRAFT") // DRAFT, PUBLISHED, ARCHIVED
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  subject Subject        @relation(fields: [subjectId], references: [id])
  teacher TeacherProfile @relation(fields: [teacherId], references: [id])
  lessons Lesson[]

  @@index([subjectId])
  @@index([teacherId])
  @@map("courses")
}

model Lesson {
  id        Int      @id @default(autoincrement())
  courseId  Int
  topicId   Int?
  title     String
  sequence  Int      @default(0)
  status    String   @default("DRAFT") // DRAFT, PUBLISHED, ARCHIVED
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  course             Course              @relation(fields: [courseId], references: [id])
  topic              Topic?              @relation(fields: [topicId], references: [id])
  materials          LearningMaterial[]
  studentProgress    StudentProgress[]
  learningPathItems  LearningPathItem[]

  @@index([courseId])
  @@index([topicId])
  @@map("lessons")
}

model LearningMaterial {
  id          Int      @id @default(autoincrement())
  lessonId    Int
  title       String
  type        String // VIDEO, TEXT, PDF, LINK, etc.
  content     String?  @db.Text
  resourceUrl String?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  lesson Lesson @relation(fields: [lessonId], references: [id])

  @@index([lessonId])
  @@map("learning_materials")
}

// ============================================================
// 10.6 QUESTIONS
// ============================================================

model QuestionBank {
  id           Int      @id @default(autoincrement())
  subjectId    Int
  topicId      Int?
  competencyId Int?
  teacherId    Int?
  name         String?
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt

  subject    Subject         @relation(fields: [subjectId], references: [id])
  topic      Topic?          @relation(fields: [topicId], references: [id])
  competency Competency?     @relation(fields: [competencyId], references: [id])
  teacher    TeacherProfile? @relation(fields: [teacherId], references: [id])
  questions  Question[]

  @@index([subjectId])
  @@index([topicId])
  @@index([competencyId])
  @@index([teacherId])
  @@map("question_banks")
}

model Question {
  id             Int      @id @default(autoincrement())
  questionBankId Int
  competencyId   Int?
  questionText   String   @db.Text
  questionType   String   @default("MULTIPLE_CHOICE") // MULTIPLE_CHOICE, TRUE_FALSE, ESSAY
  difficulty     String   @default("MEDIUM") // EASY, MEDIUM, HARD
  createdAt      DateTime @default(now())
  updatedAt      DateTime @updatedAt

  questionBank        QuestionBank          @relation(fields: [questionBankId], references: [id])
  competency          Competency?           @relation(fields: [competencyId], references: [id])
  options             QuestionOption[]
  diagnosticQuestions DiagnosticQuestion[]
  diagnosticAnswers   DiagnosticAnswer[]
  assessmentQuestions AssessmentQuestion[]
  assessmentAnswers   AssessmentAnswer[]

  @@index([questionBankId])
  @@index([competencyId])
  @@map("questions")
}

model QuestionOption {
  id         Int      @id @default(autoincrement())
  questionId Int
  optionText String   @db.Text
  isCorrect  Boolean  @default(false)
  sequence   Int      @default(0)

  question          Question           @relation(fields: [questionId], references: [id])
  diagnosticAnswers DiagnosticAnswer[]
  assessmentAnswers AssessmentAnswer[]

  @@index([questionId])
  @@map("question_options")
}

// ============================================================
// 10.7 DIAGNOSTIC
// ============================================================

model DiagnosticTest {
  id              Int      @id @default(autoincrement())
  subjectId       Int
  name            String
  durationMinutes Int?
  status          String   @default("ACTIVE") // ACTIVE, INACTIVE
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  subject   Subject              @relation(fields: [subjectId], references: [id])
  questions DiagnosticQuestion[]
  attempts  DiagnosticAttempt[]

  @@index([subjectId])
  @@map("diagnostic_tests")
}

model DiagnosticQuestion {
  id               Int @id @default(autoincrement())
  diagnosticTestId Int
  questionId       Int
  sequence         Int @default(0)

  diagnosticTest DiagnosticTest @relation(fields: [diagnosticTestId], references: [id])
  question       Question       @relation(fields: [questionId], references: [id])

  @@unique([diagnosticTestId, questionId])
  @@index([questionId])
  @@map("diagnostic_questions")
}

model DiagnosticAttempt {
  id               Int       @id @default(autoincrement())
  diagnosticTestId Int
  studentId        Int
  attemptNumber    Int       @default(1)
  score            Decimal?  @db.Decimal(5, 2)
  status           String    @default("IN_PROGRESS") // IN_PROGRESS, SUBMITTED, EXPIRED
  isFlagged        Boolean   @default(false) // indikasi kecurangan (mis. waktu jawab tidak wajar)
  flagReason       String?   @db.Text
  flaggedAt        DateTime?
  startedAt        DateTime  @default(now())
  completedAt      DateTime?

  diagnosticTest DiagnosticTest     @relation(fields: [diagnosticTestId], references: [id])
  student        StudentProfile     @relation(fields: [studentId], references: [id])
  answers        DiagnosticAnswer[]

  @@index([diagnosticTestId])
  @@index([studentId])
  @@map("diagnostic_attempts")
}

model DiagnosticAnswer {
  id                Int      @id @default(autoincrement())
  attemptId         Int
  questionId        Int
  selectedOptionId  Int?
  isCorrect         Boolean?
  timeSpentSeconds  Int?
  createdAt         DateTime @default(now())

  attempt        DiagnosticAttempt @relation(fields: [attemptId], references: [id])
  question       Question          @relation(fields: [questionId], references: [id])
  selectedOption QuestionOption?   @relation(fields: [selectedOptionId], references: [id])

  @@unique([attemptId, questionId])
  @@index([attemptId])
  @@index([questionId])
  @@index([selectedOptionId])
  @@map("diagnostic_answers")
}

// ============================================================
// 10.8 LEARNING PATH & PROGRESS
// ============================================================

model LearningPath {
  id          Int       @id @default(autoincrement())
  studentId   Int
  goalId      Int?
  title       String
  status      String    @default("ACTIVE") // ACTIVE, COMPLETED, ARCHIVED
  generatedAt DateTime  @default(now())

  student StudentProfile     @relation(fields: [studentId], references: [id])
  goal    StudentGoal?       @relation(fields: [goalId], references: [id])
  items   LearningPathItem[]

  @@index([studentId])
  @@index([goalId])
  @@map("learning_paths")
}

model LearningPathItem {
  id             Int      @id @default(autoincrement())
  learningPathId Int
  lessonId       Int?
  competencyId   Int?
  sequence       Int      @default(0)
  status         String   @default("PENDING") // PENDING, IN_PROGRESS, DONE

  learningPath LearningPath @relation(fields: [learningPathId], references: [id])
  lesson       Lesson?      @relation(fields: [lessonId], references: [id])
  competency   Competency?  @relation(fields: [competencyId], references: [id])

  @@index([learningPathId])
  @@index([lessonId])
  @@index([competencyId])
  @@map("learning_path_items")
}

model StudentProgress {
  id                 Int       @id @default(autoincrement())
  studentId          Int
  lessonId           Int
  progressPercentage Decimal   @default(0) @db.Decimal(5, 2)
  status             String    @default("NOT_STARTED") // NOT_STARTED, IN_PROGRESS, COMPLETED
  startedAt          DateTime?
  completedAt        DateTime?
  updatedAt          DateTime  @updatedAt

  student StudentProfile @relation(fields: [studentId], references: [id])
  lesson  Lesson         @relation(fields: [lessonId], references: [id])

  @@unique([studentId, lessonId])
  @@index([lessonId])
  @@map("student_progress")
}

// ============================================================
// 10.9 ASSESSMENT
// ============================================================

model Assessment {
  id              Int      @id @default(autoincrement())
  subjectId       Int
  teacherId       Int
  title           String
  type            String   @default("FORMATIVE") // FORMATIVE, SUMMATIVE
  durationMinutes Int?
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  subject   Subject              @relation(fields: [subjectId], references: [id])
  teacher   TeacherProfile       @relation(fields: [teacherId], references: [id])
  questions AssessmentQuestion[]
  attempts  AssessmentAttempt[]

  @@index([subjectId])
  @@index([teacherId])
  @@map("assessments")
}

model AssessmentQuestion {
  id           Int @id @default(autoincrement())
  assessmentId Int
  questionId   Int
  sequence     Int @default(0)
  points       Decimal @default(1) @db.Decimal(5, 2)

  assessment Assessment @relation(fields: [assessmentId], references: [id])
  question   Question   @relation(fields: [questionId], references: [id])

  @@unique([assessmentId, questionId])
  @@index([questionId])
  @@map("assessment_questions")
}

model AssessmentAttempt {
  id            Int       @id @default(autoincrement())
  assessmentId  Int
  studentId     Int
  attemptNumber Int       @default(1)
  score         Decimal?  @db.Decimal(5, 2)
  status        String    @default("IN_PROGRESS") // IN_PROGRESS, SUBMITTED, EXPIRED
  isFlagged     Boolean   @default(false) // indikasi kecurangan (mis. waktu jawab tidak wajar)
  flagReason    String?   @db.Text
  flaggedAt     DateTime?
  startedAt     DateTime  @default(now())
  completedAt   DateTime?

  assessment Assessment         @relation(fields: [assessmentId], references: [id])
  student    StudentProfile     @relation(fields: [studentId], references: [id])
  answers    AssessmentAnswer[]

  @@index([assessmentId])
  @@index([studentId])
  @@map("assessment_attempts")
}

model AssessmentAnswer {
  id               Int      @id @default(autoincrement())
  attemptId        Int
  questionId       Int
  selectedOptionId Int?
  isCorrect        Boolean?
  pointsEarned     Decimal? @db.Decimal(5, 2)
  timeSpentSeconds Int?
  createdAt        DateTime @default(now())

  attempt        AssessmentAttempt @relation(fields: [attemptId], references: [id])
  question       Question          @relation(fields: [questionId], references: [id])
  selectedOption QuestionOption?   @relation(fields: [selectedOptionId], references: [id])

  @@unique([attemptId, questionId])
  @@index([attemptId])
  @@index([questionId])
  @@index([selectedOptionId])
  @@map("assessment_answers")
}

// ============================================================
// PHASE 4 — LEARNING ENGINE & MASTERY SYSTEM
// ============================================================

model CompetencySnapshot {
  id                   Int      @id @default(autoincrement())
  studentId            Int
  competencyId         Int
  masteryScore         Decimal  @db.Decimal(5, 2)
  confidenceScore      Decimal  @db.Decimal(5, 4)
  totalAnswered        Int
  totalCorrect         Int
  masteryBucket        String // INSUFFICIENT_DATA, LEARNING_GAP, DEVELOPING, MASTERED
  triggeredByAttemptId Int // referensi lepas ke diagnostic_attempts.id atau assessment_attempts.id (lihat sourceType)
  sourceType           String // DIAGNOSTIC, ASSESSMENT (bisa diperluas: PRACTICE, dst)
  engineVersion        Int
  configVersion        Int
  createdAt            DateTime @default(now()) // append-only, tidak pernah di-update

  student    StudentProfile @relation(fields: [studentId], references: [id])
  competency Competency     @relation(fields: [competencyId], references: [id])

  @@index([studentId, competencyId, createdAt])
  @@index([triggeredByAttemptId])
  @@map("competency_snapshots")
}

model LearningEngineConfig {
  id                     Int      @id @default(autoincrement())
  alpha                  Decimal  @default(0.30) @db.Decimal(3, 2) // bobot EMA ke attempt terbaru
  difficultyEasyWeight   Decimal  @default(1.0) @db.Decimal(3, 2)
  difficultyMediumWeight Decimal  @default(1.5) @db.Decimal(3, 2)
  difficultyHardWeight   Decimal  @default(2.0) @db.Decimal(3, 2)
  masteredThreshold      Decimal  @default(80) @db.Decimal(5, 2)
  developingThreshold    Decimal  @default(60) @db.Decimal(5, 2)
  confidenceK            Decimal  @default(5) @db.Decimal(5, 2) // konstanta saturasi confidence
  minimumConfidence      Decimal  @default(0.60) @db.Decimal(3, 2) // gate INSUFFICIENT_DATA
  engineVersion          Int      @default(1)
  configVersion          Int      @default(1)
  active                 Boolean  @default(true) // hanya satu baris boleh active=true pada satu waktu
  createdAt              DateTime @default(now())
  updatedAt              DateTime @updatedAt

  @@map("learning_engine_configs")
}
FILEEOF

echo ">> Menulis src/assessments/assessments.service.ts"
mkdir -p $(dirname src/assessments/assessments.service.ts)
cat > src/assessments/assessments.service.ts << 'FILEEOF'
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EvidenceService } from '../learning-engine/evidence/evidence.service';
import { MasteryService } from '../learning-engine/mastery/mastery.service';
import type { UpdateCompetencyResult } from '../learning-engine/mastery/mastery.service';
import { CompetencySnapshotService } from '../learning-engine/snapshots/competency-snapshot.service';
import { LearningEngineConfigService } from '../learning-engine/config/learning-engine-config.service';
import { LearningPathReconciler } from '../learning-engine/learning-path/learning-path-reconciler';
import { SubmitAssessmentDto } from './dto/submit-assessment.dto';
import { detectSuspiciousTiming } from '../learning-engine/integrity/suspicious-timing-detector';

@Injectable()
export class AssessmentsService {
  constructor(
    private prisma: PrismaService,
    private evidenceService: EvidenceService,
    private masteryService: MasteryService,
    private competencySnapshotService: CompetencySnapshotService,
    private learningEngineConfigService: LearningEngineConfigService,
    private learningPathReconciler: LearningPathReconciler,
  ) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({
      where: { userId },
    });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  async startAttempt(userId: number, assessmentId: number) {
    const profile = await this.findProfileByUserId(userId);

    const assessment = await this.prisma.assessment.findUnique({
      where: { id: assessmentId },
    });

    if (!assessment) {
      throw new NotFoundException('Assessment tidak ditemukan.');
    }

    const previousAttemptsCount = await this.prisma.assessmentAttempt.count({
      where: { assessmentId, studentId: profile.id },
    });

    return this.prisma.assessmentAttempt.create({
      data: {
        assessmentId,
        studentId: profile.id,
        attemptNumber: previousAttemptsCount + 1,
        status: 'IN_PROGRESS',
      },
    });
  }

  /**
   * Sama persis alurnya dengan DiagnosticsService.submit() -- keduanya
   * memakai Learning Engine yang sama (spec Phase 4 bagian 13: "Jangan
   * membuat algoritma mastery berbeda antara Diagnostic dan Assessment").
   *
   * SATU perbedaan struktural: skor attempt di sini dihitung berbobot
   * `points` per soal (field yang memang cuma ada di AssessmentQuestion,
   * tidak ada di DiagnosticQuestion) -- bukan sekadar persen jawaban
   * benar seperti di diagnostic. Ini tetap "Assessment Score", BUKAN
   * "Mastery Score" (section 21) -- masteryScore tetap dihitung EMA lewat
   * MasteryService yang identik dengan diagnostic.
   */
  async submit(userId: number, assessmentId: number, dto: SubmitAssessmentDto) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.$transaction(async (tx) => {
      // 2. Validate attempt ownership
      const attempt = await tx.assessmentAttempt.findUnique({
        where: { id: dto.attemptId },
      });

      if (!attempt) {
        throw new NotFoundException('Attempt tidak ditemukan.');
      }
      if (attempt.studentId !== profile.id) {
        throw new ForbiddenException('Attempt ini bukan milik kamu.');
      }
      if (attempt.assessmentId !== assessmentId) {
        throw new BadRequestException(
          'Attempt ini bukan untuk assessment ini.',
        );
      }

      // 3. Validate attempt status -- idempotency guard ATOMIC, sama
      // persis polanya dengan DiagnosticsService.
      const guarded = await tx.assessmentAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException(
          'Attempt ini sudah pernah disubmit sebelumnya.',
        );
      }

      // 4. Validate submitted answers + sekaligus ambil `points` per soal
      // dalam SATU query (bukan dua query terpisah untuk validasi dan
      // untuk ambil points). Juga tolak questionId yang dikirim berulang
      // dalam satu payload (fix Bug #2 QA audit 16 Agustus 2026 -- pola
      // sama persis dengan DiagnosticsService).
      const assessmentQuestions = await tx.assessmentQuestion.findMany({
        where: { assessmentId },
        select: { questionId: true, points: true },
      });
      const pointsByQuestionId = new Map(
        assessmentQuestions.map((q) => [q.questionId, Number(q.points)]),
      );
      const seenQuestionIds = new Set<number>();

      for (const answer of dto.answers) {
        if (!pointsByQuestionId.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari assessment ini.`,
          );
        }
        if (seenQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} dikirim lebih dari sekali dalam satu submission.`,
          );
        }
        seenQuestionIds.add(answer.questionId);
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness -- SAMA PERSIS dengan diagnostic,
      // service yang dipakai pun sama (EvidenceService).
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } =
        await this.evidenceService.loadAndAggregate(tx, normalizedAnswers);

      // 8. Insert AssessmentAnswer (bulk), sekalian hitung pointsEarned
      // per jawaban dari map yang sudah di-load di step 4.
      await tx.assessmentAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          pointsEarned: a.isCorrect
            ? (pointsByQuestionId.get(a.questionId) ?? 0)
            : 0,
          timeSpentSeconds: a.timeSpentSeconds ?? undefined,
        })),
      });

      // 9-14. Per competency yang tersentuh: EMA mastery, confidence,
      // classify bucket, snapshot, reconcile learning path -- LEARNING
      // ENGINE YANG SAMA dengan diagnostic, cuma sourceType-nya beda.
      const config = await this.learningEngineConfigService.getActiveConfig(tx);
      const competencyResults: UpdateCompetencyResult[] = [];

      for (const [competencyId, evidence] of evidenceByCompetency) {
        const result = await this.masteryService.updateForCompetency(tx, {
          studentId: profile.id,
          competencyId,
          evidence,
          config,
        });

        await this.competencySnapshotService.create(tx, {
          studentId: profile.id,
          competencyId,
          masteryScore: result.newMasteryScore,
          confidenceScore: result.newConfidenceScore,
          totalAnswered: result.totalAnswered,
          totalCorrect: result.totalCorrect,
          masteryBucket: result.newBucket,
          triggeredByAttemptId: attempt.id,
          sourceType: 'ASSESSMENT',
          engineVersion: config.engineVersion,
          configVersion: config.configVersion,
        });

        if (result.bucketChanged) {
          await this.learningPathReconciler.reconcile(tx, {
            studentId: profile.id,
            competencyId,
            oldBucket: result.oldBucket,
            newBucket: result.newBucket,
          });
        }

        competencyResults.push(result);
      }

      // 15. Update AssessmentAttempt -- score berbobot points (BUKAN
      // masteryScore), & completedAt.
      let totalPossiblePoints = 0;
      let totalEarnedPoints = 0;

      for (const a of enrichedAnswers) {
        const possible = pointsByQuestionId.get(a.questionId) ?? 0;
        totalPossiblePoints += possible;
        if (a.isCorrect) {
          totalEarnedPoints += possible;
        }
      }

      const overallScore =
        totalPossiblePoints > 0
          ? (totalEarnedPoints / totalPossiblePoints) * 100
          : 0;

      // Sesi 6: deteksi timing mencurigakan -- pola identik dengan
      // DiagnosticsService, fungsi pure yang sama-sama di-reuse.
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      const updatedAttempt = await tx.assessmentAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(timingCheck.isFlagged
            ? {
                isFlagged: true,
                flagReason: timingCheck.flagReason,
                flaggedAt: new Date(),
              }
            : {}),
        },
      });

      // 17. Return learning profile.
      return {
        attempt: updatedAttempt,
        overallScore,
        competencyResults,
      };
    });
  }
}
FILEEOF

echo ">> Menulis src/assessments/dto/submit-assessment.dto.ts"
mkdir -p $(dirname src/assessments/dto/submit-assessment.dto.ts)
cat > src/assessments/dto/submit-assessment.dto.ts << 'FILEEOF'
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  ValidateNested,
} from 'class-validator';
import { SubmitAssessmentAnswerDto } from './submit-assessment-answer.dto';

export class SubmitAssessmentDto {
  @IsInt()
  attemptId: number;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => SubmitAssessmentAnswerDto)
  answers: SubmitAssessmentAnswerDto[];
}
FILEEOF

echo ">> Menulis src/diagnostics/diagnostics.service.ts"
mkdir -p $(dirname src/diagnostics/diagnostics.service.ts)
cat > src/diagnostics/diagnostics.service.ts << 'FILEEOF'
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EvidenceService } from '../learning-engine/evidence/evidence.service';
import { MasteryService } from '../learning-engine/mastery/mastery.service';
import type { UpdateCompetencyResult } from '../learning-engine/mastery/mastery.service';
import { CompetencySnapshotService } from '../learning-engine/snapshots/competency-snapshot.service';
import { LearningEngineConfigService } from '../learning-engine/config/learning-engine-config.service';
import { LearningPathReconciler } from '../learning-engine/learning-path/learning-path-reconciler';
import { SubmitDiagnosticDto } from './dto/submit-diagnostic.dto';
import { detectSuspiciousTiming } from '../learning-engine/integrity/suspicious-timing-detector';

@Injectable()
export class DiagnosticsService {
  constructor(
    private prisma: PrismaService,
    private evidenceService: EvidenceService,
    private masteryService: MasteryService,
    private competencySnapshotService: CompetencySnapshotService,
    private learningEngineConfigService: LearningEngineConfigService,
    private learningPathReconciler: LearningPathReconciler,
  ) {}

  private async findProfileByUserId(userId: number) {
    const profile = await this.prisma.studentProfile.findUnique({
      where: { userId },
    });

    if (!profile) {
      throw new NotFoundException('Profil student tidak ditemukan.');
    }

    return profile;
  }

  // Step 1 (start): buat attempt baru, status IN_PROGRESS.
  async startAttempt(userId: number, diagnosticTestId: number) {
    const profile = await this.findProfileByUserId(userId);

    const diagnosticTest = await this.prisma.diagnosticTest.findUnique({
      where: { id: diagnosticTestId },
    });

    if (!diagnosticTest) {
      throw new NotFoundException('Diagnostic test tidak ditemukan.');
    }

    const previousAttemptsCount = await this.prisma.diagnosticAttempt.count({
      where: { diagnosticTestId, studentId: profile.id },
    });

    return this.prisma.diagnosticAttempt.create({
      data: {
        diagnosticTestId,
        studentId: profile.id,
        attemptNumber: previousAttemptsCount + 1,
        status: 'IN_PROGRESS',
      },
    });
  }

  /**
   * Alur 17 langkah sesuai spec Phase 4 bagian 12, semuanya dalam SATU
   * database transaction (bagian 14: "harus diproses dalam satu database
   * transaction ... jangan sampai answer berhasil masuk tapi
   * StudentCompetency gagal update").
   */
  async submit(
    userId: number,
    diagnosticTestId: number,
    dto: SubmitDiagnosticDto,
  ) {
    const profile = await this.findProfileByUserId(userId);

    return this.prisma.$transaction(async (tx) => {
      // 2. Validate attempt ownership
      const attempt = await tx.diagnosticAttempt.findUnique({
        where: { id: dto.attemptId },
      });

      if (!attempt) {
        throw new NotFoundException('Attempt tidak ditemukan.');
      }
      if (attempt.studentId !== profile.id) {
        throw new ForbiddenException('Attempt ini bukan milik kamu.');
      }
      if (attempt.diagnosticTestId !== diagnosticTestId) {
        throw new BadRequestException(
          'Attempt ini bukan untuk diagnostic test ini.',
        );
      }

      // 3. Validate attempt status -- idempotency guard yang ATOMIC.
      // UPDATE ... WHERE status='IN_PROGRESS' mengunci baris ini di dalam
      // transaction; kalau ada request submit kedua (double-klik/retry)
      // yang datang bersamaan, salah satunya pasti dapat count=0 di sini
      // dan gagal SEBELUM sempat memproses jawaban apa pun.
      const guarded = await tx.diagnosticAttempt.updateMany({
        where: { id: attempt.id, status: 'IN_PROGRESS' },
        data: { status: 'SUBMITTED' },
      });

      if (guarded.count === 0) {
        throw new ConflictException(
          'Attempt ini sudah pernah disubmit sebelumnya.',
        );
      }

      // 4. Validate submitted answers -- questionId harus benar-benar
      // bagian dari diagnostic test ini (bukan soal dari test lain), DAN
      // tidak boleh ada questionId yang dikirim berulang kali dalam satu
      // payload (fix Bug #2 QA audit 16 Agustus 2026: sebelumnya siswa bisa
      // kirim 1 questionId yang sama puluhan kali untuk menggelembungkan
      // totalAnswered/confidence dalam satu submission).
      const validQuestions = await tx.diagnosticQuestion.findMany({
        where: { diagnosticTestId },
        select: { questionId: true },
      });
      const validQuestionIds = new Set(validQuestions.map((q) => q.questionId));
      const seenQuestionIds = new Set<number>();

      for (const answer of dto.answers) {
        if (!validQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} bukan bagian dari diagnostic test ini.`,
          );
        }
        if (seenQuestionIds.has(answer.questionId)) {
          throw new BadRequestException(
            `Question ${answer.questionId} dikirim lebih dari sekali dalam satu submission.`,
          );
        }
        seenQuestionIds.add(answer.questionId);
      }

      // 5-7. Load semua question dalam satu batch query, map ke
      // competency, hitung correctness.
      const normalizedAnswers = dto.answers.map((a) => ({
        questionId: a.questionId,
        selectedOptionId: a.selectedOptionId ?? null,
        timeSpentSeconds: a.timeSpentSeconds ?? null,
      }));

      const { enrichedAnswers, evidenceByCompetency } =
        await this.evidenceService.loadAndAggregate(tx, normalizedAnswers);

      // 8. Insert DiagnosticAnswer (bulk, bukan satu-satu).
      await tx.diagnosticAnswer.createMany({
        data: enrichedAnswers.map((a) => ({
          attemptId: attempt.id,
          questionId: a.questionId,
          selectedOptionId: a.selectedOptionId ?? undefined,
          isCorrect: a.isCorrect,
          timeSpentSeconds: a.timeSpentSeconds ?? undefined,
        })),
      });

      // 9-14. Per competency yang tersentuh: EMA mastery, confidence,
      // classify bucket, snapshot, dan reconcile learning path HANYA kalau
      // bucket-nya berubah.
      const config = await this.learningEngineConfigService.getActiveConfig(tx);
      const competencyResults: UpdateCompetencyResult[] = [];

      for (const [competencyId, evidence] of evidenceByCompetency) {
        const result = await this.masteryService.updateForCompetency(tx, {
          studentId: profile.id,
          competencyId,
          evidence,
          config,
        });

        await this.competencySnapshotService.create(tx, {
          studentId: profile.id,
          competencyId,
          masteryScore: result.newMasteryScore,
          confidenceScore: result.newConfidenceScore,
          totalAnswered: result.totalAnswered,
          totalCorrect: result.totalCorrect,
          masteryBucket: result.newBucket,
          triggeredByAttemptId: attempt.id,
          sourceType: 'DIAGNOSTIC',
          engineVersion: config.engineVersion,
          configVersion: config.configVersion,
        });

        if (result.bucketChanged) {
          await this.learningPathReconciler.reconcile(tx, {
            studentId: profile.id,
            competencyId,
            oldBucket: result.oldBucket,
            newBucket: result.newBucket,
          });
        }

        competencyResults.push(result);
      }

      // 15. Update DiagnosticAttempt -- score & completedAt (status sudah
      // SUBMITTED dari guard di step 3). Skor attempt ini SENGAJA dipisah
      // dari masteryScore (spec bagian 21: Assessment Score != Mastery
      // Score) -- ini murni persentase benar di attempt ini saja, tanpa
      // difficulty weighting maupun EMA.
      const correctCount = enrichedAnswers.filter((a) => a.isCorrect).length;
      const overallScore = (correctCount / enrichedAnswers.length) * 100;

      // Sesi 6: deteksi timing mencurigakan -- rule-based, murni fungsi,
      // dievaluasi dari jawaban attempt ini saja (belum lintas attempt).
      const timingCheck = detectSuspiciousTiming(
        enrichedAnswers.map((a) => ({ timeSpentSeconds: a.timeSpentSeconds })),
      );

      const updatedAttempt = await tx.diagnosticAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(timingCheck.isFlagged
            ? {
                isFlagged: true,
                flagReason: timingCheck.flagReason,
                flaggedAt: new Date(),
              }
            : {}),
        },
      });

      // 17. Return learning profile.
      return {
        attempt: updatedAttempt,
        overallScore,
        competencyResults,
      };
    });
  }
}
FILEEOF

echo ">> Menulis src/diagnostics/dto/submit-diagnostic.dto.ts"
mkdir -p $(dirname src/diagnostics/dto/submit-diagnostic.dto.ts)
cat > src/diagnostics/dto/submit-diagnostic.dto.ts << 'FILEEOF'
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  ValidateNested,
} from 'class-validator';
import { SubmitAnswerDto } from './submit-answer.dto';

export class SubmitDiagnosticDto {
  @IsInt()
  attemptId: number;

  @IsArray()
  @ArrayMinSize(1)
  // Batas atas kasar -- tidak ada diagnostic test realistis yang butuh
  // >200 soal dalam satu attempt. Ini murni hardening terhadap payload
  // raksasa (temuan QA audit 16 Agustus 2026, item LOW), bukan batas bisnis.
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => SubmitAnswerDto)
  answers: SubmitAnswerDto[];
}
FILEEOF

echo ">> Menulis src/learning-engine/config/learning-engine-config.service.ts"
mkdir -p $(dirname src/learning-engine/config/learning-engine-config.service.ts)
cat > src/learning-engine/config/learning-engine-config.service.ts << 'FILEEOF'
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
FILEEOF

echo ">> Menulis src/learning-engine/evidence/evidence-aggregator.spec.ts"
mkdir -p $(dirname src/learning-engine/evidence/evidence-aggregator.spec.ts)
cat > src/learning-engine/evidence/evidence-aggregator.spec.ts << 'FILEEOF'
import { aggregateEvidence, OptionLookup } from './evidence-aggregator';

describe('aggregateEvidence', () => {
  it('menghitung isCorrect dari optionLookup (per-question) dan mengelompokkan evidence per competency', () => {
    const questionLookup = new Map([
      [1, { competencyId: 100, difficulty: 'EASY' as const }],
      [2, { competencyId: 100, difficulty: 'HARD' as const }],
      [3, { competencyId: 200, difficulty: 'MEDIUM' as const }],
    ]);
    const optionLookup = new Map<number, OptionLookup>([
      [11, { questionId: 1, isCorrect: true }],
      [21, { questionId: 2, isCorrect: false }],
      [32, { questionId: 3, isCorrect: true }],
    ]);

    const result = aggregateEvidence(
      [
        { questionId: 1, selectedOptionId: 11 }, // benar
        { questionId: 2, selectedOptionId: 21 }, // salah
        { questionId: 3, selectedOptionId: 32 }, // benar
      ],
      questionLookup,
      optionLookup,
    );

    expect(result.enrichedAnswers).toHaveLength(3);
    expect(result.enrichedAnswers[0].isCorrect).toBe(true);
    expect(result.enrichedAnswers[1].isCorrect).toBe(false);
    expect(result.enrichedAnswers[2].isCorrect).toBe(true);

    expect(result.evidenceByCompetency.get(100)).toEqual([
      { difficulty: 'EASY', isCorrect: true },
      { difficulty: 'HARD', isCorrect: false },
    ]);
    expect(result.evidenceByCompetency.get(200)).toEqual([
      { difficulty: 'MEDIUM', isCorrect: true },
    ]);
  });

  it('selectedOptionId null (soal tidak dijawab) dianggap salah', () => {
    const questionLookup = new Map([
      [1, { competencyId: 100, difficulty: 'EASY' as const }],
    ]);

    const result = aggregateEvidence(
      [{ questionId: 1, selectedOptionId: null }],
      questionLookup,
      new Map(),
    );

    expect(result.enrichedAnswers[0].isCorrect).toBe(false);
  });

  it('question tanpa competency tetap masuk enrichedAnswers tapi tidak masuk evidenceByCompetency', () => {
    const questionLookup = new Map([
      [1, { competencyId: null, difficulty: 'EASY' as const }],
    ]);
    const optionLookup = new Map<number, OptionLookup>([
      [5, { questionId: 1, isCorrect: true }],
    ]);

    const result = aggregateEvidence(
      [{ questionId: 1, selectedOptionId: 5 }],
      questionLookup,
      optionLookup,
    );

    expect(result.enrichedAnswers).toHaveLength(1);
    expect(result.evidenceByCompetency.size).toBe(0);
  });

  it('melempar error kalau ada questionId yang tidak ada di lookup', () => {
    expect(() =>
      aggregateEvidence(
        [{ questionId: 999, selectedOptionId: 1 }],
        new Map(),
        new Map(),
      ),
    ).toThrow();
  });

  // Regression test untuk Bug #1 (QA audit 16 Agustus 2026): sebelum fix,
  // sistem cuma cek "apakah optionId ini benar untuk soal MANAPUN" lewat
  // Set global, jadi satu optionId benar bisa "dipakai ulang" untuk soal
  // lain dan dianggap benar juga. Test ini membuktikan itu SEKARANG DITOLAK.
  describe('Bug #1 fix: option harus milik question yang sedang dijawab', () => {
    it('optionId benar untuk question 1, dikirim ulang sebagai jawaban question 2 -> DITOLAK (bukan dianggap benar)', () => {
      const questionLookup = new Map([
        [1, { competencyId: 100, difficulty: 'EASY' as const }],
        [2, { competencyId: 100, difficulty: 'EASY' as const }],
      ]);
      // optionId 11 adalah jawaban BENAR untuk question 1 saja.
      const optionLookup = new Map<number, OptionLookup>([
        [11, { questionId: 1, isCorrect: true }],
      ]);

      const result = aggregateEvidence(
        [
          { questionId: 1, selectedOptionId: 11 }, // benar-benar milik question 1 -> benar
          { questionId: 2, selectedOptionId: 11 }, // exploit: pakai optionId question 1 untuk question 2
        ],
        questionLookup,
        optionLookup,
      );

      expect(result.enrichedAnswers[0].isCorrect).toBe(true);
      expect(result.enrichedAnswers[1].isCorrect).toBe(false); // HARUS salah, bukan ikut benar
    });

    it('optionId benar tapi dikirim untuk question yang sama sekali tidak terhubung ke option itu -> tetap salah', () => {
      const questionLookup = new Map([
        [5, { competencyId: 300, difficulty: 'MEDIUM' as const }],
        [6, { competencyId: 300, difficulty: 'MEDIUM' as const }],
      ]);
      const optionLookup = new Map<number, OptionLookup>([
        [99, { questionId: 5, isCorrect: true }],
      ]);

      const result = aggregateEvidence(
        [{ questionId: 6, selectedOptionId: 99 }],
        questionLookup,
        optionLookup,
      );

      expect(result.enrichedAnswers[0].isCorrect).toBe(false);
    });
  });
});
FILEEOF

echo ">> Menulis src/learning-engine/evidence/evidence-aggregator.ts"
mkdir -p $(dirname src/learning-engine/evidence/evidence-aggregator.ts)
cat > src/learning-engine/evidence/evidence-aggregator.ts << 'FILEEOF'
import { BadRequestException } from '@nestjs/common';
import { AnswerEvidence, Difficulty } from '../learning-engine.types';

export interface RawSubmittedAnswer {
  questionId: number;
  selectedOptionId: number | null;
  timeSpentSeconds?: number | null;
}

export interface QuestionLookup {
  competencyId: number | null;
  difficulty: Difficulty;
}

// Dulu cuma Set<number> dari option ID yang "benar" secara GLOBAL — itu yang
// jadi celah Bug #1 (lihat evidence.service.ts). Sekarang per-option kita
// tahu dia MILIK question mana, supaya bisa divalidasi option itu benar
// UNTUK SOAL YANG SEDANG DIJAWAB, bukan cuma "benar untuk soal manapun".
export interface OptionLookup {
  questionId: number;
  isCorrect: boolean;
}

export interface EnrichedAnswer extends RawSubmittedAnswer {
  isCorrect: boolean;
  difficulty: Difficulty;
  competencyId: number | null;
}

export interface EvidenceAggregationResult {
  enrichedAnswers: EnrichedAnswer[];
  evidenceByCompetency: Map<number, AnswerEvidence[]>;
}

/**
 * Gabungkan raw submitted answers dengan data question/option yang SUDAH
 * di-batch-load sebelumnya (lihat EvidenceService), lalu kelompokkan
 * evidence per competency. Fungsi ini murni — tidak menyentuh Prisma sama
 * sekali — supaya gampang di-unit-test tanpa database.
 *
 * Soal yang tidak terhubung ke competency manapun (competencyId null) tetap
 * masuk ke enrichedAnswers (untuk disimpan sebagai jawaban), tapi TIDAK ikut
 * dikelompokkan ke evidenceByCompetency karena tidak ada mastery yang perlu
 * di-update untuknya.
 *
 * KEAMANAN (fix Bug #1): sebuah selectedOptionId dianggap benar HANYA kalau
 * option itu benar-benar milik questionId yang sedang dijawab DAN isCorrect
 * true. Sebelumnya sistem cuma cek "apakah option ID ini benar untuk soal
 * manapun" (Set global) — itu memungkinkan siswa mengirim satu optionId
 * yang benar untuk SEMUA soal lain dalam payload dan dianggap semuanya benar.
 */
export function aggregateEvidence(
  rawAnswers: RawSubmittedAnswer[],
  questionLookup: Map<number, QuestionLookup>,
  optionLookup: Map<number, OptionLookup>,
): EvidenceAggregationResult {
  const enrichedAnswers: EnrichedAnswer[] = [];
  const evidenceByCompetency = new Map<number, AnswerEvidence[]>();

  for (const raw of rawAnswers) {
    const question = questionLookup.get(raw.questionId);

    if (!question) {
      throw new BadRequestException(
        `Question ${raw.questionId} tidak ditemukan.`,
      );
    }

    let isCorrect = false;
    if (raw.selectedOptionId !== null) {
      const option = optionLookup.get(raw.selectedOptionId);
      // option harus ada DAN benar-benar milik question ini -- inilah inti
      // fix-nya. Kalau siswa kirim optionId dari soal lain, option.questionId
      // tidak akan cocok dengan raw.questionId, jadi tetap dianggap salah.
      isCorrect =
        !!option && option.questionId === raw.questionId && option.isCorrect;
    }

    const enriched: EnrichedAnswer = {
      ...raw,
      isCorrect,
      difficulty: question.difficulty,
      competencyId: question.competencyId,
    };
    enrichedAnswers.push(enriched);

    if (question.competencyId !== null) {
      const evidenceList =
        evidenceByCompetency.get(question.competencyId) ?? [];
      evidenceList.push({ difficulty: question.difficulty, isCorrect });
      evidenceByCompetency.set(question.competencyId, evidenceList);
    }
  }

  return { enrichedAnswers, evidenceByCompetency };
}
FILEEOF

echo ">> Menulis src/learning-engine/evidence/evidence.service.ts"
mkdir -p $(dirname src/learning-engine/evidence/evidence.service.ts)
cat > src/learning-engine/evidence/evidence.service.ts << 'FILEEOF'
import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import {
  aggregateEvidence,
  EvidenceAggregationResult,
  OptionLookup,
  QuestionLookup,
  RawSubmittedAnswer,
} from './evidence-aggregator';
import { Difficulty } from '../learning-engine.types';

@Injectable()
export class EvidenceService {
  /**
   * Batch-load semua question + option yang relevan dalam MAKSIMAL dua
   * query (bukan satu query per jawaban), lalu kelompokkan evidence-nya
   * per competency. Ini yang memenuhi aturan "1 query -> load questions"
   * di spec Phase 4 — jumlah query TIDAK bertambah seiring jumlah jawaban.
   *
   * `tx` wajib berupa Prisma transaction client (bukan this.prisma
   * langsung), supaya batch load ini konsisten dalam transaksi yang sama
   * dengan insert answer / update StudentCompetency di Sesi 4/5 nanti.
   */
  async loadAndAggregate(
    tx: Prisma.TransactionClient,
    rawAnswers: RawSubmittedAnswer[],
  ): Promise<EvidenceAggregationResult> {
    if (rawAnswers.length === 0) {
      return { enrichedAnswers: [], evidenceByCompetency: new Map() };
    }

    const questionIds = [...new Set(rawAnswers.map((a) => a.questionId))];
    const selectedOptionIds = [
      ...new Set(
        rawAnswers
          .map((a) => a.selectedOptionId)
          .filter((id): id is number => id !== null),
      ),
    ];

    const [questions, selectedOptions] = await Promise.all([
      tx.question.findMany({
        where: { id: { in: questionIds } },
        select: { id: true, competencyId: true, difficulty: true },
      }),
      // Fix Bug #1: dulu query ini di-filter `isCorrect: true` lalu hasilnya
      // dijadikan Set<number> global, jadi sistem cuma tahu "option ID ini
      // benar", tanpa tahu benar UNTUK SOAL MANA. Sekarang kita ambil
      // questionId pemilik tiap option (regardless benar/salah) supaya bisa
      // divalidasi option itu benar-benar milik soal yang sedang dijawab.
      selectedOptionIds.length > 0
        ? tx.questionOption.findMany({
            where: { id: { in: selectedOptionIds } },
            select: { id: true, questionId: true, isCorrect: true },
          })
        : Promise.resolve([]),
    ]);

    const questionLookup = new Map<number, QuestionLookup>(
      questions.map((q) => [
        q.id,
        {
          competencyId: q.competencyId,
          difficulty: q.difficulty as Difficulty,
        },
      ]),
    );

    const optionLookup = new Map<number, OptionLookup>(
      selectedOptions.map((o) => [
        o.id,
        { questionId: o.questionId, isCorrect: o.isCorrect },
      ]),
    );

    return aggregateEvidence(rawAnswers, questionLookup, optionLookup);
  }
}
FILEEOF

echo ">> Menulis test/assessments.e2e-spec.ts"
mkdir -p $(dirname test/assessments.e2e-spec.ts)
cat > test/assessments.e2e-spec.ts << 'FILEEOF'
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  createTestApp,
  registerStudent,
  registerTeacher,
  createAssessmentFixture,
  AssessmentFixture,
} from './utils/test-app.helper';

/**
 * AssessmentsService berbagi EvidenceService yang IDENTIK dengan
 * DiagnosticsService (lihat komentar di assessments.service.ts: "Jangan
 * membuat algoritma mastery berbeda antara Diagnostic dan Assessment").
 * Artinya Bug #1 dan Bug #2 dari QA audit 16 Agustus 2026 berlaku sama
 * persis di sini -- suite ini membuktikan fix-nya juga berlaku di jalur
 * Assessment, bukan cuma Diagnostic.
 *
 * Ini BUKAN pengganti full e2e suite (happy path/rollback/performance)
 * seperti punya Diagnostic -- itu masih item terpisah di roadmap
 * ("Salin pattern e2e test dari Diagnostic ke Assessment", rekomendasi
 * #5 di audit). Fokus suite ini murni security regression.
 */
describe('Assessments submission security (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fixture: AssessmentFixture;

  beforeAll(async () => {
    const ctx = await createTestApp();
    app = ctx.app;
    prisma = ctx.prisma;
    fixture = await createAssessmentFixture(prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  function buildAllCorrectAnswers() {
    return fixture.questions.map((q) => ({
      questionId: q.questionId,
      selectedOptionId: q.correctOptionId,
      timeSpentSeconds: 20,
    }));
  }

  describe('security: Bug #1 -- cross-question answer key exploit', () => {
    it('optionId benar milik soal lain dipakai ulang untuk semua soal -> TIDAK dianggap semuanya benar', async () => {
      const student = await registerStudent(app, 'asmt-exploit-cross-question');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const knownCorrectOptionId = fixture.questions[0].correctOptionId;
      const exploitAnswers = fixture.questions.map((q) => ({
        questionId: q.questionId,
        selectedOptionId: knownCorrectOptionId,
        timeSpentSeconds: 5,
      }));

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: exploitAnswers })
        .expect(201);

      // Assessment score dihitung berbobot points (bukan persen jawaban
      // benar biasa) -- cuma soal pertama yang benar-benar benar, jadi
      // skornya harus 1/6 dari total points, BUKAN 100%.
      const totalPoints = fixture.questions.reduce(
        (sum, q) => sum + q.points,
        0,
      );
      const expectedScore = (fixture.questions[0].points / totalPoints) * 100;
      expect(submitRes.body.data.overallScore).toBe(expectedScore);
      expect(submitRes.body.data.overallScore).not.toBe(100);

      const answers = await prisma.assessmentAnswer.findMany({
        where: { attemptId },
      });
      const correctAnswers = answers.filter((a) => a.isCorrect);
      expect(correctAnswers).toHaveLength(1);
      expect(correctAnswers[0].questionId).toBe(
        fixture.questions[0].questionId,
      );
    });
  });

  describe('security: Bug #2 -- duplicate questionId dalam satu submission', () => {
    it('questionId yang sama dikirim berulang kali dalam satu payload -> ditolak 400, tidak ada evidence yang tergelembung', async () => {
      const student = await registerStudent(
        app,
        'asmt-exploit-duplicate-question',
      );

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const easyQuestion = fixture.questions.find(
        (q) => q.difficulty === 'EASY',
      )!;
      const duplicateAnswers = Array.from({ length: 10 }, () => ({
        questionId: easyQuestion.questionId,
        selectedOptionId: easyQuestion.correctOptionId,
        timeSpentSeconds: 5,
      }));

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: duplicateAnswers })
        .expect(400);

      const answerCount = await prisma.assessmentAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(0);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });

  describe('security: RBAC -- role TEACHER tidak boleh akses endpoint assessments milik STUDENT', () => {
    it('TEACHER coba start attempt -> 403', async () => {
      const teacher = await registerTeacher(app, 'asmt-rbac-teacher-start');

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(403);
    });

    it('TEACHER coba submit -> 403 (bahkan dengan attemptId milik student lain)', async () => {
      const student = await registerStudent(app, 'asmt-rbac-victim');
      const teacher = await registerTeacher(app, 'asmt-rbac-teacher-submit');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(403);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });
});
FILEEOF

echo ">> Menulis test/diagnostics.e2e-spec.ts"
mkdir -p $(dirname test/diagnostics.e2e-spec.ts)
cat > test/diagnostics.e2e-spec.ts << 'FILEEOF'
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  createTestApp,
  registerStudent,
  registerTeacher,
  createDiagnosticFixture,
  DiagnosticFixture,
} from './utils/test-app.helper';

describe('Diagnostics submission (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fixture: DiagnosticFixture;

  beforeAll(async () => {
    const ctx = await createTestApp();
    app = ctx.app;
    prisma = ctx.prisma;
    fixture = await createDiagnosticFixture(prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  // Semua jawaban benar -> attemptAccuracy 100% -> first-attempt rule
  // (spec bagian 5.1): masteryScore = attemptAccuracy, bukan EMA.
  function buildAllCorrectAnswers() {
    return fixture.questions.map((q) => ({
      questionId: q.questionId,
      selectedOptionId: q.correctOptionId,
      timeSpentSeconds: 20,
    }));
  }

  it('happy path: submit diagnostic membuat StudentCompetency + CompetencySnapshot untuk tiap competency yang tersentuh', async () => {
    const student = await registerStudent(app, 'happy-path');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);

    const attemptId = startRes.body.data.id;

    const submitRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers: buildAllCorrectAnswers() })
      .expect(201);

    expect(submitRes.body.success).toBe(true);
    expect(submitRes.body.data.overallScore).toBe(100);
    expect(submitRes.body.data.competencyResults).toHaveLength(2);

    const studentProfile = await prisma.studentProfile.findUnique({
      where: { userId: student.userId },
    });

    for (const competencyId of fixture.competencyIds) {
      const competencyState = await prisma.studentCompetency.findUnique({
        where: {
          studentId_competencyId: {
            studentId: studentProfile!.id,
            competencyId,
          },
        },
      });

      expect(competencyState).not.toBeNull();
      expect(competencyState!.totalAnswered).toBe(3); // 3 soal per competency
      expect(competencyState!.totalCorrect).toBe(3);
      expect(Number(competencyState!.masteryScore)).toBe(100); // first-attempt rule

      // Fix temuan QA audit #5 (16 Agustus 2026): test lama tidak pernah
      // assert masteryBucket. Dengan config default (confidenceK=5,
      // minimumConfidence=0.60), 3 jawaban -> confidence = 1-e^(-3/5) ≈
      // 0.451, DI BAWAH ambang 0.60. Jadi walau masteryScore=100, bucket
      // HARUS INSUFFICIENT_DATA, bukan MASTERED -- confidence gate
      // dievaluasi duluan sebelum threshold mastery (lihat mastery-classifier.ts).
      expect(competencyState!.masteryBucket).toBe('INSUFFICIENT_DATA');

      const snapshots = await prisma.competencySnapshot.findMany({
        where: { studentId: studentProfile!.id, competencyId },
      });
      expect(snapshots).toHaveLength(1);
      expect(snapshots[0].sourceType).toBe('DIAGNOSTIC');
      expect(snapshots[0].triggeredByAttemptId).toBe(attemptId);
      expect(snapshots[0].masteryBucket).toBe('INSUFFICIENT_DATA');
    }
  });

  it('duplicate submission: submit attempt yang sama dua kali -> request kedua ditolak 409, counter tidak dobel', async () => {
    const student = await registerStudent(app, 'duplicate-sub');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    const answers = buildAllCorrectAnswers();

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers })
      .expect(201);

    // Submit kedua, attempt yang sama persis -> harus 409, bukan sukses lagi.
    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers })
      .expect(409);

    const studentProfile = await prisma.studentProfile.findUnique({
      where: { userId: student.userId },
    });

    const answerCount = await prisma.diagnosticAnswer.count({
      where: { attemptId },
    });
    expect(answerCount).toBe(fixture.questions.length); // bukan 2x lipat

    const competencyState = await prisma.studentCompetency.findUnique({
      where: {
        studentId_competencyId: {
          studentId: studentProfile!.id,
          competencyId: fixture.competencyIds[0],
        },
      },
    });
    expect(competencyState!.totalAnswered).toBe(3); // bukan 6
  });

  it('security: student lain tidak bisa submit attempt milik student ini (403)', async () => {
    const owner = await registerStudent(app, 'owner');
    const intruder = await registerStudent(app, 'intruder');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${intruder.accessToken}`)
      .send({ attemptId, answers: buildAllCorrectAnswers() })
      .expect(403);

    // Attempt milik owner harus tetap IN_PROGRESS, belum tersentuh sama sekali.
    const attempt = await prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });
    expect(attempt!.status).toBe('IN_PROGRESS');
  });

  it('rollback: question tidak valid di tengah batch -> tidak ada partial write (answer/competency tidak berubah)', async () => {
    const student = await registerStudent(app, 'rollback');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    const answers = [
      ...buildAllCorrectAnswers(),
      { questionId: 999999, selectedOptionId: null, timeSpentSeconds: 10 }, // question invalid
    ];

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers })
      .expect(400);

    // Karena gagal di dalam transaction, TIDAK BOLEH ada answer yang
    // ke-insert sama sekali, dan attempt harus tetap IN_PROGRESS (guard
    // idempotency di step 3 juga ikut ter-rollback).
    const answerCount = await prisma.diagnosticAnswer.count({
      where: { attemptId },
    });
    expect(answerCount).toBe(0);

    const attempt = await prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });
    expect(attempt!.status).toBe('IN_PROGRESS');
  });

  it('performance sanity: submit 6 jawaban lintas 2 competency selesai dalam waktu wajar (bukti tidak ada full-history recomputation)', async () => {
    const student = await registerStudent(app, 'perf-sanity');

    const startRes = await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .expect(201);
    const attemptId = startRes.body.data.id;

    const startTime = Date.now();

    await request(app.getHttpServer())
      .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
      .set('Authorization', `Bearer ${student.accessToken}`)
      .send({ attemptId, answers: buildAllCorrectAnswers() })
      .expect(201);

    const elapsedMs = Date.now() - startTime;

    // Sanity check kasar, bukan micro-benchmark presisi: kalau submission
    // diam-diam melakukan full-history recomputation (mis. query semua
    // historical answer per competency), elapsed time akan melonjak jauh
    // di atas ini seiring data bertambah. 2 detik jauh di atas ekspektasi
    // normal (harusnya <200ms lokal) tapi cukup toleran untuk CI yang lambat.
    expect(elapsedMs).toBeLessThan(2000);
  });

  // ============================================================
  // Regression test untuk temuan QA audit 16 Agustus 2026.
  // ============================================================

  describe('security: Bug #1 -- cross-question answer key exploit', () => {
    it('optionId benar milik soal lain dipakai ulang untuk semua soal -> TIDAK dianggap semuanya benar', async () => {
      const student = await registerStudent(app, 'exploit-cross-question');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      // Exploit: pakai SATU optionId yang benar (milik soal pertama) untuk
      // SEMUA soal lain dalam payload. Sebelum fix, ini bikin semua jawaban
      // dianggap benar (overallScore 100%) walau cuma 1 optionId yang valid.
      const knownCorrectOptionId = fixture.questions[0].correctOptionId;
      const exploitAnswers = fixture.questions.map((q) => ({
        questionId: q.questionId,
        selectedOptionId: knownCorrectOptionId,
        timeSpentSeconds: 5,
      }));

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: exploitAnswers })
        .expect(201);

      // Cuma soal pertama (pemilik asli optionId itu) yang benar-benar
      // benar. Sisanya harus dianggap salah, BUKAN ikut 100%.
      const expectedCorrectCount = 1;
      const expectedScore =
        (expectedCorrectCount / fixture.questions.length) * 100;
      expect(submitRes.body.data.overallScore).toBe(expectedScore);
      expect(submitRes.body.data.overallScore).not.toBe(100);

      const answers = await prisma.diagnosticAnswer.findMany({
        where: { attemptId },
      });
      const correctAnswers = answers.filter((a) => a.isCorrect);
      expect(correctAnswers).toHaveLength(expectedCorrectCount);
      expect(correctAnswers[0].questionId).toBe(
        fixture.questions[0].questionId,
      );
    });
  });

  describe('security: Bug #2 -- duplicate questionId dalam satu submission', () => {
    it('questionId yang sama dikirim berulang kali dalam satu payload -> ditolak 400, tidak ada evidence yang tergelembung', async () => {
      const student = await registerStudent(app, 'exploit-duplicate-question');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      // Exploit: satu soal mudah yang jawabannya diketahui, dikirim
      // berulang kali untuk menggelembungkan totalAnswered/confidence.
      const easyQuestion = fixture.questions.find(
        (q) => q.difficulty === 'EASY',
      )!;
      const duplicateAnswers = Array.from({ length: 10 }, () => ({
        questionId: easyQuestion.questionId,
        selectedOptionId: easyQuestion.correctOptionId,
        timeSpentSeconds: 5,
      }));

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: duplicateAnswers })
        .expect(400);

      // Karena ditolak validasi di dalam transaction, TIDAK BOLEH ada
      // answer yang ke-insert dan attempt harus tetap IN_PROGRESS -- sama
      // seperti test rollback untuk question tidak valid di atas.
      const answerCount = await prisma.diagnosticAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(0);

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });

  describe('security: RBAC -- role TEACHER tidak boleh akses endpoint diagnostics milik STUDENT', () => {
    it('TEACHER coba start attempt -> 403', async () => {
      const teacher = await registerTeacher(app, 'rbac-teacher-start');

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(403);
    });

    it('TEACHER coba submit -> 403 (bahkan dengan attemptId milik student lain)', async () => {
      const student = await registerStudent(app, 'rbac-victim');
      const teacher = await registerTeacher(app, 'rbac-teacher-submit');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(403);

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('IN_PROGRESS');
    });
  });
});
FILEEOF

echo ">> Menulis test/utils/test-app.helper.ts"
mkdir -p $(dirname test/utils/test-app.helper.ts)
cat > test/utils/test-app.helper.ts << 'FILEEOF'
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/prisma/prisma.service';
import { ResponseInterceptor } from '../../src/common/interceptors/response.interceptor';
import { AllExceptionsFilter } from '../../src/common/filters/http-exception.filter';

/**
 * Bootstrap app persis sama konfigurasinya dengan main.ts (prefix, pipe,
 * interceptor, filter) -- supaya e2e test benar-benar merepresentasikan
 * perilaku production, bukan default NestJS testing module yang polos.
 */
export async function createTestApp(): Promise<{
  app: INestApplication;
  prisma: PrismaService;
}> {
  const moduleFixture: TestingModule = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleFixture.createNestApplication();

  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );
  app.useGlobalInterceptors(new ResponseInterceptor());
  app.useGlobalFilters(new AllExceptionsFilter());

  await app.init();

  const prisma = app.get(PrismaService);

  return { app, prisma };
}

export interface TestStudent {
  accessToken: string;
  userId: number;
}

/**
 * Register + login satu akun STUDENT baru, return access token siap pakai.
 * Email dibuat unik per pemanggilan (timestamp + random) supaya test bisa
 * dijalankan berulang kali tanpa bentrok "email sudah terdaftar".
 */
export async function registerStudent(
  app: INestApplication,
  namePrefix: string,
): Promise<TestStudent> {
  const uniqueSuffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
  const email = `${namePrefix}-${uniqueSuffix}@e2e-test.local`;

  const res = await request(app.getHttpServer())
    .post('/api/v1/auth/register')
    .send({ email, password: 'password123', name: namePrefix, role: 'STUDENT' })
    .expect(201);

  const accessToken: string = res.body.data.accessToken;
  const payload = JSON.parse(
    Buffer.from(accessToken.split('.')[1], 'base64').toString(),
  );

  return { accessToken, userId: payload.sub };
}

/**
 * Sama seperti registerStudent, tapi role TEACHER -- dipakai untuk
 * negative RBAC test (memastikan TEACHER ditolak dari endpoint
 * /diagnostics dan /assessments yang khusus STUDENT).
 */
export async function registerTeacher(
  app: INestApplication,
  namePrefix: string,
): Promise<TestStudent> {
  const uniqueSuffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
  const email = `${namePrefix}-${uniqueSuffix}@e2e-test.local`;

  const res = await request(app.getHttpServer())
    .post('/api/v1/auth/register')
    .send({ email, password: 'password123', name: namePrefix, role: 'TEACHER' })
    .expect(201);

  const accessToken: string = res.body.data.accessToken;
  const payload = JSON.parse(
    Buffer.from(accessToken.split('.')[1], 'base64').toString(),
  );

  return { accessToken, userId: payload.sub };
}

export interface DiagnosticFixture {
  subjectId: number;
  competencyIds: number[];
  diagnosticTestId: number;
  // questionId -> { correctOptionId }
  questions: Array<{
    questionId: number;
    correctOptionId: number;
    competencyId: number;
    difficulty: string;
  }>;
}

/**
 * Bikin fixture akademik minimal langsung lewat Prisma (bukan lewat API --
 * lebih cepat dan tidak bergantung ke module Subjects/Competencies yang
 * punya RBAC admin-only sendiri). 2 competency, 6 question (3 per
 * competency, campuran difficulty) supaya cukup untuk test batch/incremental.
 */
export async function createDiagnosticFixture(
  prisma: PrismaService,
): Promise<DiagnosticFixture> {
  const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;

  const subject = await prisma.subject.create({
    data: { code: `E2E-SUBJ-${suffix}`, name: 'E2E Test Subject' },
  });

  const competencyA = await prisma.competency.create({
    data: {
      subjectId: subject.id,
      code: `E2E-COMP-A-${suffix}`,
      name: 'Competency A',
    },
  });
  const competencyB = await prisma.competency.create({
    data: {
      subjectId: subject.id,
      code: `E2E-COMP-B-${suffix}`,
      name: 'Competency B',
    },
  });

  const questionBank = await prisma.questionBank.create({
    data: { subjectId: subject.id, name: 'E2E Test Bank' },
  });

  const difficulties: Array<'EASY' | 'MEDIUM' | 'HARD'> = [
    'EASY',
    'MEDIUM',
    'HARD',
  ];
  const questions: DiagnosticFixture['questions'] = [];

  for (const competency of [competencyA, competencyB]) {
    for (const difficulty of difficulties) {
      const question = await prisma.question.create({
        data: {
          questionBankId: questionBank.id,
          competencyId: competency.id,
          questionText: `Soal ${difficulty} untuk ${competency.name}`,
          difficulty,
        },
      });

      const correctOption = await prisma.questionOption.create({
        data: {
          questionId: question.id,
          optionText: 'Benar',
          isCorrect: true,
          sequence: 1,
        },
      });
      await prisma.questionOption.create({
        data: {
          questionId: question.id,
          optionText: 'Salah',
          isCorrect: false,
          sequence: 2,
        },
      });

      questions.push({
        questionId: question.id,
        correctOptionId: correctOption.id,
        competencyId: competency.id,
        difficulty,
      });
    }
  }

  const diagnosticTest = await prisma.diagnosticTest.create({
    data: { subjectId: subject.id, name: 'E2E Diagnostic Test' },
  });

  for (const [index, q] of questions.entries()) {
    await prisma.diagnosticQuestion.create({
      data: {
        diagnosticTestId: diagnosticTest.id,
        questionId: q.questionId,
        sequence: index,
      },
    });
  }

  return {
    subjectId: subject.id,
    competencyIds: [competencyA.id, competencyB.id],
    diagnosticTestId: diagnosticTest.id,
    questions,
  };
}

export interface AssessmentFixture {
  subjectId: number;
  competencyIds: number[];
  assessmentId: number;
  // questionId -> { correctOptionId, points }
  questions: Array<{
    questionId: number;
    correctOptionId: number;
    competencyId: number;
    difficulty: string;
    points: number;
  }>;
}

/**
 * Sama persis polanya dengan createDiagnosticFixture, tapi untuk Assessment
 * (butuh `points` per soal di AssessmentQuestion, yang tidak ada di
 * DiagnosticQuestion, dan `teacherId` wajib di Assessment). Dipakai untuk
 * regression test security Bug #1/#2 yang audit temukan sama-sama berlaku
 * di AssessmentsService karena berbagi EvidenceService yang identik dengan
 * DiagnosticsService.
 */
export async function createAssessmentFixture(
  prisma: PrismaService,
): Promise<AssessmentFixture> {
  const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;

  const subject = await prisma.subject.create({
    data: {
      code: `E2E-ASMT-SUBJ-${suffix}`,
      name: 'E2E Test Subject (Assessment)',
    },
  });

  const competencyA = await prisma.competency.create({
    data: {
      subjectId: subject.id,
      code: `E2E-ASMT-COMP-A-${suffix}`,
      name: 'Competency A',
    },
  });
  const competencyB = await prisma.competency.create({
    data: {
      subjectId: subject.id,
      code: `E2E-ASMT-COMP-B-${suffix}`,
      name: 'Competency B',
    },
  });

  const questionBank = await prisma.questionBank.create({
    data: { subjectId: subject.id, name: 'E2E Test Bank (Assessment)' },
  });

  const difficulties: Array<'EASY' | 'MEDIUM' | 'HARD'> = [
    'EASY',
    'MEDIUM',
    'HARD',
  ];
  const questions: AssessmentFixture['questions'] = [];

  for (const competency of [competencyA, competencyB]) {
    for (const difficulty of difficulties) {
      const question = await prisma.question.create({
        data: {
          questionBankId: questionBank.id,
          competencyId: competency.id,
          questionText: `Soal ${difficulty} untuk ${competency.name}`,
          difficulty,
        },
      });

      const correctOption = await prisma.questionOption.create({
        data: {
          questionId: question.id,
          optionText: 'Benar',
          isCorrect: true,
          sequence: 1,
        },
      });
      await prisma.questionOption.create({
        data: {
          questionId: question.id,
          optionText: 'Salah',
          isCorrect: false,
          sequence: 2,
        },
      });

      questions.push({
        questionId: question.id,
        correctOptionId: correctOption.id,
        competencyId: competency.id,
        difficulty,
        points: 10,
      });
    }
  }

  // Assessment butuh teacherId (wajib, bukan optional) -- bikin
  // User+TeacherProfile langsung lewat Prisma, bukan lewat API, biar
  // fixture ini tetap independen dari module Auth/Teachers.
  const teacherRole = await prisma.role.findUniqueOrThrow({
    where: { name: 'TEACHER' },
  });
  const teacherUser = await prisma.user.create({
    data: {
      email: `e2e-assessment-teacher-${suffix}@e2e-test.local`,
      password: 'unused-fixture-password-hash',
      roleId: teacherRole.id,
    },
  });
  const teacherProfile = await prisma.teacherProfile.create({
    data: { userId: teacherUser.id, name: 'E2E Fixture Teacher' },
  });

  const assessment = await prisma.assessment.create({
    data: {
      subjectId: subject.id,
      teacherId: teacherProfile.id,
      title: 'E2E Assessment',
      type: 'FORMATIVE',
    },
  });

  for (const [index, q] of questions.entries()) {
    await prisma.assessmentQuestion.create({
      data: {
        assessmentId: assessment.id,
        questionId: q.questionId,
        sequence: index,
        points: q.points,
      },
    });
  }

  return {
    subjectId: subject.id,
    competencyIds: [competencyA.id, competencyB.id],
    assessmentId: assessment.id,
    questions,
  };
}
FILEEOF


echo ""
echo ">> Semua file berhasil ditulis."
echo ""
echo "Langkah selanjutnya (WAJIB berurutan):"
echo ""
echo "1. Buat migration untuk unique constraint baru (@@unique([attemptId, questionId])"
echo "   di DiagnosticAnswer & AssessmentAnswer -- ini pengaman DB-level Bug #2):"
echo "   npx prisma migrate dev --name fix_qa_audit_unique_attempt_question"
echo ""
echo "2. Generate ulang Prisma client:"
echo "   npx prisma generate"
echo ""
echo "3. Jalankan test suite (semuanya harus PASS, termasuk test regression exploit baru):"
echo "   npm run test              # unit test, termasuk evidence-aggregator.spec.ts"
echo "   npm run test:e2e          # e2e test, termasuk assessments.e2e-spec.ts yang baru"
echo ""
echo "4. Restart server: npm run start:dev"
echo ""
echo "Test yang WAJIB kamu perhatikan hasilnya (paste ke chat kalau ada yang FAIL):"
echo "  - evidence-aggregator.spec.ts > 'Bug #1 fix: option harus milik question yang sedang dijawab'"
echo "  - diagnostics.e2e-spec.ts > 'security: Bug #1' dan 'security: Bug #2' dan 'security: RBAC'"
echo "  - assessments.e2e-spec.ts (file baru) > sama seperti di atas tapi untuk jalur Assessment"
echo "  - diagnostics.e2e-spec.ts > happy path (sekarang assert masteryBucket juga)"
