import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { createTestApp, registerStudent, registerTeacher } from './utils/test-app.helper';

/**
 * Phase 5 (Security): section 17.3 dokumen master eksplisit minta
 * "Teacher tidak dapat mengubah content milik teacher lain tanpa
 * permission" -- kode ownership check-nya SUDAH ADA sejak awal
 * (ForbiddenException di Courses/Lessons/MaterialsService), tapi
 * sebelum ini TIDAK ADA satu test pun yang membuktikannya. Ini persis
 * kelas bug yang bikin diagnostics.service.ts kehilangan fitur secara
 * diam-diam beberapa kali -- kode tanpa test itu rapuh.
 */
describe('Content ownership security (Course -> Lesson -> Material) (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    const ctx = await createTestApp();
    app = ctx.app;
    prisma = ctx.prisma;
  });

  afterAll(async () => {
    await app.close();
  });

  async function createSubject() {
    const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    return prisma.subject.create({
      data: { code: `E2E-CONTENT-${suffix}`, name: 'E2E Content Subject' },
    });
  }

  describe('RBAC: hanya TEACHER yang boleh membuat content', () => {
    it('STUDENT coba bikin course -> 403', async () => {
      const student = await registerStudent(app, 'content-rbac-student');
      const subject = await createSubject();

      await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${student.accessToken}`)
        .send({ subjectId: subject.id, title: 'Percobaan Siswa' })
        .expect(403);
    });
  });

  describe('ownership: TEACHER lain tidak bisa ubah course/lesson/material milik TEACHER ini', () => {
    it('full chain: course, lesson, dan material -> semuanya ditolak (403) untuk teacher B', async () => {
      const teacherA = await registerTeacher(app, 'content-owner-a');
      const teacherB = await registerTeacher(app, 'content-intruder-b');
      const subject = await createSubject();

      // Teacher A bikin course -> lesson -> material, rantai lengkap.
      const courseRes = await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ subjectId: subject.id, title: 'Course milik A' })
        .expect(201);
      const courseId = courseRes.body.data.id;

      const lessonRes = await request(app.getHttpServer())
        .post('/api/v1/lessons')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ courseId, title: 'Lesson milik A' })
        .expect(201);
      const lessonId = lessonRes.body.data.id;

      const materialRes = await request(app.getHttpServer())
        .post('/api/v1/materials')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ lessonId, title: 'Materi milik A', type: 'TEXT', content: 'isi materi' })
        .expect(201);
      const materialId = materialRes.body.data.id;

      // Teacher B coba UPDATE ketiganya -> semua harus 403.
      await request(app.getHttpServer())
        .put(`/api/v1/courses/${courseId}`)
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ title: 'Diubah paksa oleh B' })
        .expect(403);

      await request(app.getHttpServer())
        .put(`/api/v1/lessons/${lessonId}`)
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ title: 'Diubah paksa oleh B' })
        .expect(403);

      await request(app.getHttpServer())
        .put(`/api/v1/materials/${materialId}`)
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ title: 'Diubah paksa oleh B' })
        .expect(403);

      // Teacher B juga tidak bisa numpang nambah lesson/material BARU
      // di course/lesson milik A.
      await request(app.getHttpServer())
        .post('/api/v1/lessons')
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ courseId, title: 'Lesson nyelonong dari B' })
        .expect(403);

      await request(app.getHttpServer())
        .post('/api/v1/materials')
        .set('Authorization', `Bearer ${teacherB.accessToken}`)
        .send({ lessonId, title: 'Materi nyelonong dari B', type: 'TEXT' })
        .expect(403);

      // Sanity check: data ASLI tidak berubah sama sekali gara-gara
      // percobaan B di atas.
      const course = await prisma.course.findUniqueOrThrow({ where: { id: courseId } });
      expect(course.title).toBe('Course milik A');
    });

    it('teacher A tetap bisa update miliknya sendiri (positive case, bukan cuma negative)', async () => {
      const teacherA = await registerTeacher(app, 'content-owner-positive');
      const subject = await createSubject();

      const courseRes = await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ subjectId: subject.id, title: 'Judul awal' })
        .expect(201);

      const updateRes = await request(app.getHttpServer())
        .put(`/api/v1/courses/${courseRes.body.data.id}`)
        .set('Authorization', `Bearer ${teacherA.accessToken}`)
        .send({ title: 'Judul sudah direvisi' })
        .expect(200);

      expect(updateRes.body.data.title).toBe('Judul sudah direvisi');
    });
  });

  describe('visibility: course DRAFT default tidak muncul di listing publik', () => {
    it('course baru (DRAFT default) tidak ikut ke GET /courses tanpa filter status', async () => {
      const teacher = await registerTeacher(app, 'content-visibility');
      const subject = await createSubject();

      const courseRes = await request(app.getHttpServer())
        .post('/api/v1/courses')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .send({ subjectId: subject.id, title: 'Course draft tersembunyi' })
        .expect(201);

      const listRes = await request(app.getHttpServer())
        .get('/api/v1/courses')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(200);

      const found = listRes.body.data.find((c: { id: number }) => c.id === courseRes.body.data.id);
      expect(found).toBeUndefined();

      // Tapi tetap ketemu kalau filter status eksplisit diminta.
      const draftListRes = await request(app.getHttpServer())
        .get('/api/v1/courses?status=DRAFT')
        .set('Authorization', `Bearer ${teacher.accessToken}`)
        .expect(200);
      const foundDraft = draftListRes.body.data.find(
        (c: { id: number }) => c.id === courseRes.body.data.id,
      );
      expect(foundDraft).toBeDefined();
    });
  });
});
