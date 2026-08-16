#!/usr/bin/env bash
# apply_teacher_engine_forward_compat_16aug2026.sh
#
# KelasXtra backend -- forward-compat improvement ditemukan dari evaluasi
# desain "keputusan bisnis Phase 4" (duration soft-flag, diagnostic 1x cap
# + void, assessment cooldown) terhadap Learning Engine & Teacher Engine
# yang akan datang.
#
# MASALAH: cap 1x diagnostic dan cooldown 24 jam assessment saat ini
# HARDCODED di service code. Ini benar untuk V1, tapi begitu Teacher Engine
# (V2) datang dan guru butuh atur ini per-item (mis. quiz mingguan vs
# latihan bebas), bakal butuh migration + rewrite service lagi.
#
# FIX: tambah kolom nullable/default-preserving di schema SEKARANG:
#   - DiagnosticTest.allowMultipleAttempts (Boolean, default false)
#   - Assessment.cooldownHours (Int?, null = pakai default 24 jam)
# Service dibaca dari kolom ini dengan fallback ke perilaku LAMA persis --
# TIDAK ADA perubahan perilaku default, murni menyiapkan tempat untuk
# Teacher Engine menulis config nanti tanpa migration lagi.
#
# Idempotent -- aman dijalankan berkali-kali.
# Jalankan dari ROOT folder project backend (kelasxtra-super-app).

set -e

if [ ! -f "package.json" ] || [ ! -d "prisma" ]; then
  echo "Jalankan script ini dari root folder backend (kelasxtra-super-app), bukan dari folder lain."
  exit 1
fi

echo ">> Menulis file yang diperbarui..."

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
  voidedDiagnosticAttempts DiagnosticAttempt[] @relation("VoidedDiagnosticAttempts")

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

  // Keputusan bisnis 16 Agustus 2026: diagnostic dibatasi 1x per siswa
  // (lihat DiagnosticsService.startAttempt) supaya starting-point learning
  // path tidak bisa di-"shopping". Field ini DIBUAT SEKARANG (walau belum
  // ada UI teacher untuk mengubahnya) supaya kalau nanti Teacher Engine
  // butuh per-test override (mis. diagnostic ulangan semester vs diagnostic
  // awal), itu cuma butuh baca kolom ini -- BUKAN migration + rewrite
  // service lagi. Default false = perilaku SEKARANG (1x, tidak berubah).
  allowMultipleAttempts Boolean @default(false)

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
  status           String    @default("IN_PROGRESS") // IN_PROGRESS, SUBMITTED, EXPIRED, VOID
  isFlagged        Boolean   @default(false) // indikasi kecurangan (mis. waktu jawab tidak wajar / lewat durationMinutes)
  flagReason       String?   @db.Text
  flaggedAt        DateTime?
  startedAt        DateTime  @default(now())
  completedAt      DateTime?

  // Keputusan bisnis: diagnostic test dibatasi 1x per siswa per test
  // (lihat DiagnosticsService.startAttempt) -- kalau perlu diulang (mis.
  // ada kendala teknis saat tes), ADMIN/TEACHER bisa "void" attempt lama
  // ini lewat POST /diagnostics/attempts/:id/void, bukan menghapusnya,
  // supaya riwayat tetap bisa ditelusuri.
  voidedAt       DateTime?
  voidReason     String?   @db.Text
  voidedByUserId Int?

  diagnosticTest DiagnosticTest     @relation(fields: [diagnosticTestId], references: [id])
  student        StudentProfile     @relation(fields: [studentId], references: [id])
  voidedByUser   User?              @relation("VoidedDiagnosticAttempts", fields: [voidedByUserId], references: [id])
  answers        DiagnosticAnswer[]

  @@index([diagnosticTestId])
  @@index([studentId])
  @@index([voidedByUserId])
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

  // Sama alasannya dengan DiagnosticTest.allowMultipleAttempts: cooldown
  // 24 jam saat ini masih konstanta global di AssessmentsService. Kolom
  // ini nullable -- null berarti "pakai default service" (24 jam,
  // perilaku SEKARANG, tidak berubah). Nanti kalau guru butuh atur beda
  // per assessment (mis. quiz mingguan vs latihan bebas), tinggal isi
  // kolom ini lewat Teacher Engine, tanpa migration baru.
  cooldownHours   Int?

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

  // Keputusan bisnis (16 Agustus 2026): assessment BOLEH diulang -- beda
  // peran dari diagnostic (lihat DiagnosticsService.startAttempt). Ini
  // memang cara sistem "belajar" tentang perkembangan siswa dari waktu ke
  // waktu (confidence naik pelan-pelan lewat EMA seiring makin banyak
  // evidence masuk). Yang dibatasi bukan JUMLAH ulangnya, tapi JEDANYA --
  // supaya siswa tidak spam submit berkali-kali dalam semenit cuma buat
  // menggelembungkan confidence score secara artifisial, bukan belajar beneran.
  //
  // Ini DEFAULT fallback -- assessment.cooldownHours (nullable) bisa
  // override per-item kalau nanti Teacher Engine butuh itu, tanpa
  // migration/rewrite lagi (lihat komentar di schema.prisma).
  private static readonly DEFAULT_ATTEMPT_COOLDOWN_HOURS = 24;

  async startAttempt(userId: number, assessmentId: number) {
    const profile = await this.findProfileByUserId(userId);

    const assessment = await this.prisma.assessment.findUnique({
      where: { id: assessmentId },
    });

    if (!assessment) {
      throw new NotFoundException('Assessment tidak ditemukan.');
    }

    const latestAttempt = await this.prisma.assessmentAttempt.findFirst({
      where: { assessmentId, studentId: profile.id },
      orderBy: { startedAt: 'desc' },
    });

    // Attempt lama masih IN_PROGRESS -- lanjutkan yang sama, jangan bikin duplikat.
    if (latestAttempt?.status === 'IN_PROGRESS') {
      return latestAttempt;
    }

    if (latestAttempt?.status === 'SUBMITTED' && latestAttempt.completedAt) {
      const cooldownHours =
        assessment.cooldownHours ??
        AssessmentsService.DEFAULT_ATTEMPT_COOLDOWN_HOURS;
      const hoursSinceLastAttempt =
        (Date.now() - latestAttempt.completedAt.getTime()) / 3_600_000;

      if (hoursSinceLastAttempt < cooldownHours) {
        const hoursRemaining = Math.ceil(cooldownHours - hoursSinceLastAttempt);
        throw new ConflictException(
          `Kamu baru saja mengerjakan assessment ini. Coba lagi dalam ${hoursRemaining} jam.`,
        );
      }
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

      // Keputusan bisnis (16 Agustus 2026, item #3): sama seperti diagnostic
      // -- durationMinutes jadi SOFT FLAG, bukan blokir keras. Assessment di
      // Kelasxtra berperan sebagai latihan/check-in berkala (bukan ujian
      // formal sekali-jalan), jadi menolak submit yang telat bertentangan
      // dengan tujuan mendorong siswa terus berlatih.
      const assessment = await tx.assessment.findUnique({
        where: { id: assessmentId },
        select: { durationMinutes: true },
      });
      const elapsedMinutes =
        (Date.now() - attempt.startedAt.getTime()) / 60_000;
      const isOverDuration =
        assessment?.durationMinutes != null &&
        elapsedMinutes > assessment.durationMinutes;

      const flagReasons = [
        ...(timingCheck.isFlagged && timingCheck.flagReason
          ? [timingCheck.flagReason]
          : []),
        ...(isOverDuration
          ? [
              `Melebihi batas waktu pengerjaan (${assessment!.durationMinutes} menit, selesai dalam ${Math.round(elapsedMinutes)} menit).`,
            ]
          : []),
      ];
      const isFlagged = timingCheck.isFlagged || isOverDuration;

      const updatedAttempt = await tx.assessmentAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(isFlagged
            ? {
                isFlagged: true,
                flagReason: flagReasons.join(' | '),
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

  // Fix #9 (QA audit 16 Agustus 2026): sebelumnya hasil assessment CUMA
  // ada di response submit() sekali itu saja -- kalau siswa nutup
  // halamannya atau mau lihat lagi besok, tidak ada cara sama sekali.
  // Endpoint ini disebut eksplisit di dokumen master (section 12.6) tapi
  // belum pernah diimplementasikan.
  //
  // Tanpa query attemptId -> ambil attempt SUBMITTED paling baru untuk
  // assessment ini (hasil "current" yang paling relevan buat siswa).
  // Dengan attemptId -> lihat attempt spesifik (riwayat, karena sekarang
  // assessment boleh diulang -- lihat startAttempt).
  async getResults(userId: number, assessmentId: number, attemptId?: number) {
    const profile = await this.findProfileByUserId(userId);

    const attempt = attemptId
      ? await this.prisma.assessmentAttempt.findUnique({
          where: { id: attemptId },
        })
      : await this.prisma.assessmentAttempt.findFirst({
          where: { assessmentId, studentId: profile.id, status: 'SUBMITTED' },
          orderBy: { completedAt: 'desc' },
        });

    if (!attempt) {
      throw new NotFoundException(
        attemptId
          ? 'Attempt tidak ditemukan.'
          : 'Belum ada attempt yang disubmit untuk assessment ini.',
      );
    }
    if (attempt.studentId !== profile.id) {
      throw new ForbiddenException('Attempt ini bukan milik kamu.');
    }
    if (attempt.assessmentId !== assessmentId) {
      throw new BadRequestException('Attempt ini bukan untuk assessment ini.');
    }
    if (attempt.status !== 'SUBMITTED') {
      throw new BadRequestException(
        'Attempt ini belum disubmit, belum ada hasil.',
      );
    }

    const answers = await this.prisma.assessmentAnswer.findMany({
      where: { attemptId: attempt.id },
      include: {
        question: {
          select: {
            id: true,
            questionText: true,
            difficulty: true,
            competencyId: true,
          },
        },
      },
    });

    // Snapshot mastery yang di-trigger OLEH attempt spesifik ini --
    // append-only, jadi ini rekonstruksi akurat dari competencyResults
    // yang dulu cuma sempat dikembalikan sekali di response submit().
    const competencySnapshots = await this.prisma.competencySnapshot.findMany({
      where: { triggeredByAttemptId: attempt.id, sourceType: 'ASSESSMENT' },
    });

    return { attempt, answers, competencySnapshots };
  }
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

  // Keputusan bisnis (16 Agustus 2026): diagnostic test itu "titik awal"
  // (starting point) buat learning path siswa, BUKAN latihan yang boleh
  // diulang bebas -- kalau boleh diulang tanpa batas, siswa bisa "diagnostic
  // shopping" (coba berkali-kali sampai dapat hasil yang menguntungkan),
  // dan starting point yang dipakai buat rekomendasi belajar jadi tidak
  // jujur. Assessment/latihan TIDAK kena aturan ini (lihat
  // AssessmentsService) -- itu memang harus boleh diulang seiring waktu,
  // beda peran dengan diagnostic.
  async startAttempt(userId: number, diagnosticTestId: number) {
    const profile = await this.findProfileByUserId(userId);

    const diagnosticTest = await this.prisma.diagnosticTest.findUnique({
      where: { id: diagnosticTestId },
    });

    if (!diagnosticTest) {
      throw new NotFoundException('Diagnostic test tidak ditemukan.');
    }

    const latestAttempt = await this.prisma.diagnosticAttempt.findFirst({
      where: { diagnosticTestId, studentId: profile.id },
      orderBy: { startedAt: 'desc' },
    });

    if (
      latestAttempt?.status === 'SUBMITTED' &&
      !diagnosticTest.allowMultipleAttempts
    ) {
      throw new ConflictException(
        'Kamu sudah menyelesaikan diagnostic test ini. Diagnostic test hanya bisa dikerjakan sekali -- hubungi guru/admin kalau butuh mengulang.',
      );
    }

    // Attempt lama masih IN_PROGRESS (mis. tab ditutup sebelum submit) --
    // lanjutkan attempt yang sama, jangan bikin duplikat.
    if (latestAttempt?.status === 'IN_PROGRESS') {
      return latestAttempt;
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

  // ADMIN/TEACHER only (ditegakkan di controller lewat @Roles). "Void"
  // dipilih daripada delete supaya riwayat attempt asli tetap bisa
  // ditelusuri -- siapa yang reset, kapan, dan alasannya apa.
  async voidAttempt(actorUserId: number, attemptId: number, reason?: string) {
    const attempt = await this.prisma.diagnosticAttempt.findUnique({
      where: { id: attemptId },
    });

    if (!attempt) {
      throw new NotFoundException('Attempt tidak ditemukan.');
    }

    if (attempt.status === 'VOID') {
      throw new ConflictException('Attempt ini sudah di-void sebelumnya.');
    }

    return this.prisma.diagnosticAttempt.update({
      where: { id: attemptId },
      data: {
        status: 'VOID',
        voidedAt: new Date(),
        voidReason: reason,
        voidedByUserId: actorUserId,
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

      // Keputusan bisnis (16 Agustus 2026, item #3): durationMinutes DITEGAKKAN
      // sebagai SOFT FLAG, bukan blokir keras -- attempt yang telat tetap
      // diterima & tetap dihitung skornya (siswa tidak dihukum kalau
      // internetnya lelet), tapi ditandai isFlagged supaya guru/admin bisa
      // menilai sendiri lewat data, bukan lewat sistem yang menolak mentah-mentah.
      const diagnosticTest = await tx.diagnosticTest.findUnique({
        where: { id: diagnosticTestId },
        select: { durationMinutes: true },
      });
      const elapsedMinutes =
        (Date.now() - attempt.startedAt.getTime()) / 60_000;
      const isOverDuration =
        diagnosticTest?.durationMinutes != null &&
        elapsedMinutes > diagnosticTest.durationMinutes;

      const flagReasons = [
        ...(timingCheck.isFlagged && timingCheck.flagReason
          ? [timingCheck.flagReason]
          : []),
        ...(isOverDuration
          ? [
              `Melebihi batas waktu pengerjaan (${diagnosticTest!.durationMinutes} menit, selesai dalam ${Math.round(elapsedMinutes)} menit).`,
            ]
          : []),
      ];
      const isFlagged = timingCheck.isFlagged || isOverDuration;

      const updatedAttempt = await tx.diagnosticAttempt.update({
        where: { id: attempt.id },
        data: {
          score: overallScore,
          completedAt: new Date(),
          ...(isFlagged
            ? {
                isFlagged: true,
                flagReason: flagReasons.join(' | '),
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

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: assessment
  // BOLEH diulang (beda dari diagnostic) -- yang dibatasi cuma jedanya
  // (cooldown), bukan jumlahnya. Lihat komentar
  // AssessmentsService.DEFAULT_ATTEMPT_COOLDOWN_HOURS.
  // ============================================================

  describe('business rule: assessment boleh diulang tapi dengan cooldown', () => {
    it('attempt kedua sebelum cooldown selesai -> 409, setelah cooldown lewat -> boleh lagi', async () => {
      const student = await registerStudent(app, 'cooldown-test');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const firstAttemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId: firstAttemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      // Langsung coba lagi -- masih dalam cooldown 24 jam -> 409.
      const blockedRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(409);
      expect(blockedRes.body.message).toContain('jam');

      // Mundurkan completedAt attempt pertama 25 jam -- simulasikan cooldown
      // 24 jam sudah lewat, tanpa perlu benar-benar menunggu di dalam test.
      const twentyFiveHoursAgo = new Date(Date.now() - 25 * 3_600_000);
      await prisma.assessmentAttempt.update({
        where: { id: firstAttemptId },
        data: { completedAt: twentyFiveHoursAgo },
      });

      const secondStartRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStartRes.body.data.id).not.toBe(firstAttemptId);
      expect(secondStartRes.body.data.attemptNumber).toBe(2);
    });

    it('attempt IN_PROGRESS yang belum disubmit -> start lagi mengembalikan attempt yang sama, bukan bikin duplikat', async () => {
      const student = await registerStudent(app, 'asmt-resume-test');

      const firstStart = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      const secondStart = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStart.body.data.id).toBe(firstStart.body.data.id);
    });
  });

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: durationMinutes
  // ditegakkan sebagai SOFT FLAG (isFlagged), bukan blokir keras -- sama
  // persis polanya dengan diagnostic (lihat diagnostics.e2e-spec.ts).
  // ============================================================

  describe('business rule: durationMinutes ditegakkan sebagai soft flag, bukan blokir', () => {
    it('submit melebihi durationMinutes -> tetap diterima (201) tapi attempt ditandai isFlagged', async () => {
      // Assessment khusus dengan durationMinutes ketat, pakai teacherId &
      // soal yang sama dari fixture (tidak perlu bikin teacher/bank baru).
      const baseAssessment = await prisma.assessment.findUniqueOrThrow({
        where: { id: fixture.assessmentId },
      });
      const timedAssessment = await prisma.assessment.create({
        data: {
          subjectId: fixture.subjectId,
          teacherId: baseAssessment.teacherId,
          title: 'E2E Timed Assessment',
          type: 'FORMATIVE',
          durationMinutes: 1,
        },
      });
      for (const [index, q] of fixture.questions.entries()) {
        await prisma.assessmentQuestion.create({
          data: {
            assessmentId: timedAssessment.id,
            questionId: q.questionId,
            sequence: index,
            points: q.points,
          },
        });
      }

      const student = await registerStudent(app, 'asmt-duration-flag');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${timedAssessment.id}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const tenMinutesAgo = new Date(Date.now() - 10 * 60_000);
      await prisma.assessmentAttempt.update({
        where: { id: attemptId },
        data: { startedAt: tenMinutesAgo },
      });

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${timedAssessment.id}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201); // TETAP diterima -- soft flag, bukan blokir keras.

      expect(submitRes.body.data.overallScore).toBe(100);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.isFlagged).toBe(true);
      expect(attempt!.flagReason).toContain('Melebihi batas waktu');
    });
  });

  // ============================================================
  // Regression test untuk temuan QA audit #6: sama seperti diagnostic,
  // ini membuktikan idempotency guard tetap atomic walau dua request
  // submit dikirim bersamaan persis (Promise.all), bukan berurutan.
  // ============================================================

  describe('concurrency: dua request submit bersamaan persis (Promise.all)', () => {
    it('tepat satu yang sukses (201), satu lagi ditolak (409) -- bukan dua-duanya sukses / dua-duanya gagal', async () => {
      const student = await registerStudent(app, 'asmt-race-condition');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const answers = buildAllCorrectAnswers();

      const [resA, resB] = await Promise.all([
        request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
        request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
      ]);

      const statuses = [resA.status, resB.status].sort((a, b) => a - b);
      expect(statuses).toEqual([201, 409]);

      const answerCount = await prisma.assessmentAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(fixture.questions.length);

      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('SUBMITTED');
    });
  });

  // ============================================================
  // Regression test untuk temuan QA audit #9: endpoint GET
  // /assessments/:id/results yang disebut di dokumen master (section
  // 12.6) tapi belum pernah diimplementasikan sebelum ini -- hasil cuma
  // pernah ada di response submit() sekali itu saja.
  // ============================================================

  describe('GET /assessments/:id/results', () => {
    it('setelah submit -> bisa lihat hasilnya lagi lewat GET (bukan cuma sekali di response submit)', async () => {
      const student = await registerStudent(app, 'results-endpoint');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      const resultsRes = await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(200);

      expect(resultsRes.body.data.attempt.id).toBe(attemptId);
      expect(resultsRes.body.data.attempt.status).toBe('SUBMITTED');
      expect(resultsRes.body.data.answers).toHaveLength(
        fixture.questions.length,
      );
      expect(resultsRes.body.data.competencySnapshots.length).toBeGreaterThan(
        0,
      );
    });

    it('belum pernah submit -> 404, bukan array kosong yang membingungkan', async () => {
      const student = await registerStudent(app, 'results-none-yet');

      await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(404);
    });

    it('security: student lain tidak bisa lihat hasil attempt milik student ini lewat ?attemptId', async () => {
      const owner = await registerStudent(app, 'results-owner');
      const intruder = await registerStudent(app, 'results-intruder');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
        .set('Authorization', `Bearer ${owner.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
        .set('Authorization', `Bearer ${owner.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      await request(app.getHttpServer())
        .get(
          `/api/v1/assessments/${fixture.assessmentId}/results?attemptId=${attemptId}`,
        )
        .set('Authorization', `Bearer ${intruder.accessToken}`)
        .expect(403);
    });

    it('TEACHER tidak boleh akses endpoint ini sama sekali (403, RBAC STUDENT-only)', async () => {
      const teacher = await registerTeacher(app, 'results-rbac-teacher');

      await request(app.getHttpServer())
        .get(`/api/v1/assessments/${fixture.assessmentId}/results`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(403);
    });
  });

  // ============================================================
  // Regression test: Assessment.cooldownHours override. Sama alasannya
  // dengan DiagnosticTest.allowMultipleAttempts -- field ini forward-compat
  // untuk Teacher Engine, test ini membuktikan override-nya benar-benar
  // dibaca service (bukan cuma ada di schema tanpa dipakai).
  // ============================================================

  describe('config: Assessment.cooldownHours override menggantikan default 24 jam', () => {
    it('cooldownHours=0 -> attempt kedua langsung boleh tanpa nunggu', async () => {
      await prisma.assessment.update({
        where: { id: fixture.assessmentId },
        data: { cooldownHours: 0 },
      });

      try {
        const student = await registerStudent(app, 'cooldown-override');

        const firstStart = await request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .expect(201);

        await request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({
            attemptId: firstStart.body.data.id,
            answers: buildAllCorrectAnswers(),
          })
          .expect(201);

        // Beda dengan default 24 jam (409 di test 'business rule' di atas)
        // -- dengan cooldownHours=0 ini HARUS 201, langsung boleh lagi.
        const secondStart = await request(app.getHttpServer())
          .post(`/api/v1/assessments/${fixture.assessmentId}/start`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .expect(201);

        expect(secondStart.body.data.id).not.toBe(firstStart.body.data.id);
      } finally {
        await prisma.assessment.update({
          where: { id: fixture.assessmentId },
          data: { cooldownHours: null },
        });
      }
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

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: diagnostic
  // dibatasi 1x per siswa per test (bukan latihan yang boleh diulang
  // bebas -- lihat komentar DiagnosticsService.startAttempt), dengan
  // jalur reset lewat ADMIN/TEACHER "void" attempt lama.
  // ============================================================

  describe('business rule: diagnostic dibatasi 1x, ADMIN/TEACHER bisa void untuk reset', () => {
    it('attempt kedua ke diagnostic test yang sama -> 409, lalu void oleh TEACHER -> siswa bisa attempt lagi', async () => {
      const student = await registerStudent(app, 'cap-test');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const firstAttemptId = startRes.body.data.id;

      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId: firstAttemptId, answers: buildAllCorrectAnswers() })
        .expect(201);

      // Attempt sudah SUBMITTED -- attempt kedua harus ditolak.
      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(409);

      // STUDENT sendiri tidak boleh void attempt-nya sendiri (RBAC).
      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/attempts/${firstAttemptId}/void`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ reason: 'coba reset sendiri' })
        .expect(403);

      // TEACHER void attempt lama -- jalur reset yang benar.
      const teacher = await registerTeacher(app, 'cap-test-teacher');
      const voidRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/attempts/${firstAttemptId}/void`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ reason: 'kendala teknis saat tes pertama' })
        .expect(201);

      expect(voidRes.body.data.status).toBe('VOID');
      expect(voidRes.body.data.voidedByUserId).toBe(teacher.userId);

      // Void attempt yang sama dua kali -> 409, bukan diam-diam sukses lagi.
      await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/attempts/${firstAttemptId}/void`)
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ reason: 'coba void lagi' })
        .expect(409);

      // Sekarang attempt baru boleh dimulai lagi.
      const secondStartRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStartRes.body.data.id).not.toBe(firstAttemptId);
      expect(secondStartRes.body.data.attemptNumber).toBe(2);
    });

    it('attempt IN_PROGRESS yang belum disubmit -> start lagi mengembalikan attempt yang sama, bukan bikin duplikat', async () => {
      const student = await registerStudent(app, 'resume-test');

      const firstStart = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      const secondStart = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);

      expect(secondStart.body.data.id).toBe(firstStart.body.data.id);
    });
  });

  // ============================================================
  // Regression test untuk keputusan bisnis 16 Agustus 2026: durationMinutes
  // ditegakkan sebagai SOFT FLAG (isFlagged), bukan blokir keras -- attempt
  // yang telat tetap diterima & tetap dihitung skornya.
  // ============================================================

  describe('business rule: durationMinutes ditegakkan sebagai soft flag, bukan blokir', () => {
    it('submit melebihi durationMinutes -> tetap diterima (201) tapi attempt ditandai isFlagged', async () => {
      // Diagnostic test khusus dengan durationMinutes ketat, pakai soal
      // yang sama dari fixture (tidak perlu bikin question bank baru).
      const timedTest = await prisma.diagnosticTest.create({
        data: {
          subjectId: fixture.subjectId,
          name: 'E2E Timed Diagnostic',
          durationMinutes: 1,
        },
      });
      for (const [index, q] of fixture.questions.entries()) {
        await prisma.diagnosticQuestion.create({
          data: {
            diagnosticTestId: timedTest.id,
            questionId: q.questionId,
            sequence: index,
          },
        });
      }

      const student = await registerStudent(app, 'duration-flag');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${timedTest.id}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      // Backdate startedAt -- simulasikan siswa sudah mengerjakan 10 menit,
      // padahal batas waktunya cuma 1 menit. Lebih cepat & lebih stabil
      // daripada benar-benar menunggu di dalam test.
      const tenMinutesAgo = new Date(Date.now() - 10 * 60_000);
      await prisma.diagnosticAttempt.update({
        where: { id: attemptId },
        data: { startedAt: tenMinutesAgo },
      });

      const submitRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${timedTest.id}/submit`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ attemptId, answers: buildAllCorrectAnswers() })
        .expect(201); // TETAP diterima -- soft flag, bukan blokir keras.

      expect(submitRes.body.data.overallScore).toBe(100); // skor tetap dihitung normal

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.isFlagged).toBe(true);
      expect(attempt!.flagReason).toContain('Melebihi batas waktu');
    });
  });

  // ============================================================
  // Regression test untuk temuan QA audit #6: test duplicate submission
  // yang sudah ada sebelumnya (di atas) submit BERURUTAN (await satu-satu),
  // itu belum benar-benar membuktikan idempotency guard atomic di level
  // database. Test ini mengirim dua request submit BERSAMAAN PERSIS lewat
  // Promise.all -- baru ini bukti yang sebenarnya.
  // ============================================================

  describe('concurrency: dua request submit bersamaan persis (Promise.all)', () => {
    it('tepat satu yang sukses (201), satu lagi ditolak (409) -- bukan dua-duanya sukses / dua-duanya gagal', async () => {
      const student = await registerStudent(app, 'race-condition');

      const startRes = await request(app.getHttpServer())
        .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
        .set('Authorization', `Bearer ${student.accessToken}`)
        .expect(201);
      const attemptId = startRes.body.data.id;

      const answers = buildAllCorrectAnswers();

      // Promise.all, BUKAN await satu-satu -- dua request submit
      // dikirim di waktu yang nyaris bersamaan persis, membuktikan
      // idempotency guard (updateMany WHERE status=IN_PROGRESS) memang
      // atomic di level database, bukan cuma aman kalau dites berurutan.
      const [resA, resB] = await Promise.all([
        request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
        request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({ attemptId, answers }),
      ]);

      const statuses = [resA.status, resB.status].sort((a, b) => a - b);
      expect(statuses).toEqual([201, 409]);

      // Jawaban tidak boleh kedobel walau dua request diproses bersamaan.
      const answerCount = await prisma.diagnosticAnswer.count({
        where: { attemptId },
      });
      expect(answerCount).toBe(fixture.questions.length);

      const attempt = await prisma.diagnosticAttempt.findUnique({
        where: { id: attemptId },
      });
      expect(attempt!.status).toBe('SUBMITTED');
    });
  });

  // ============================================================
  // Regression test: DiagnosticTest.allowMultipleAttempts override.
  // Field ini ditambahkan supaya cap 1x bisa dikonfigurasi per-test
  // (forward-compat untuk Teacher Engine) tanpa migration lagi nanti --
  // test ini membuktikan override-nya benar-benar berfungsi, bukan cuma
  // ada di schema tapi tidak pernah dibaca service.
  // ============================================================

  describe('config: DiagnosticTest.allowMultipleAttempts=true melewati cap 1x', () => {
    it('diagnostic test dengan allowMultipleAttempts=true -> siswa bisa attempt lagi TANPA perlu di-void', async () => {
      await prisma.diagnosticTest.update({
        where: { id: fixture.diagnosticTestId },
        data: { allowMultipleAttempts: true },
      });

      try {
        const student = await registerStudent(app, 'allow-multiple-attempts');

        const firstStart = await request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .expect(201);

        await request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/submit`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .send({
            attemptId: firstStart.body.data.id,
            answers: buildAllCorrectAnswers(),
          })
          .expect(201);

        // Beda dengan default (409 di test 'business rule' di atas) --
        // dengan allowMultipleAttempts=true ini HARUS 201, bukan ditolak,
        // dan TANPA perlu void dulu.
        const secondStart = await request(app.getHttpServer())
          .post(`/api/v1/diagnostics/${fixture.diagnosticTestId}/start`)
          .set('Authorization', `Bearer ${student.accessToken}`)
          .expect(201);

        expect(secondStart.body.data.id).not.toBe(firstStart.body.data.id);
        expect(secondStart.body.data.attemptNumber).toBe(2);
      } finally {
        // Reset supaya tidak bocor ke test lain yang pakai fixture yang sama.
        await prisma.diagnosticTest.update({
          where: { id: fixture.diagnosticTestId },
          data: { allowMultipleAttempts: false },
        });
      }
    });
  });
});
FILEEOF


echo ""
echo ">> Semua file berhasil ditulis."
echo ""
echo "Langkah selanjutnya (WAJIB berurutan):"
echo ""
echo "1. Migration untuk 2 kolom baru (allowMultipleAttempts, cooldownHours):"
echo "   npx prisma migrate dev --name teacher_engine_forward_compat_config"
echo ""
echo "2. Generate ulang Prisma client:"
echo "   npx prisma generate"
echo ""
echo "3. Jalankan test suite -- semua yang lama harus TETAP PASS (bukti default"
echo "   tidak berubah), plus 2 test baru yang membuktikan override-nya jalan:"
echo "   npm run test"
echo "   npm run test:e2e"
echo ""
echo "Test baru yang WAJIB kamu perhatikan:"
echo "  - diagnostics.e2e-spec.ts > 'config: DiagnosticTest.allowMultipleAttempts=true melewati cap 1x'"
echo "  - assessments.e2e-spec.ts > 'config: Assessment.cooldownHours override menggantikan default 24 jam'"
echo ""
echo "4. Restart server: npm run start:dev"
