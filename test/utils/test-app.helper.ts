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
