import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './users/users.module';
import { AuthModule } from './auth/auth.module';
import { StudentsModule } from './students/students.module';
import { TeachersModule } from './teachers/teachers.module';
import { SubjectsModule } from './subjects/subjects.module';
import { TopicsModule } from './topics/topics.module';
import { CompetenciesModule } from './competencies/competencies.module';
import { CommonModule } from './common/common.module';
import { DiagnosticsModule } from './diagnostics/diagnostics.module';
import { AssessmentsModule } from './assessments/assessments.module';

@Module({
  imports: [
    // Rate limit default: 100 request/menit per IP (section 14 dokumen
    // master: "Endpoint sensitif harus memiliki validation dan rate
    // limiting"). Endpoint yang lebih sensitif (register/login) sudah
    // punya limit lebih ketat lewat @Throttle({...}) di AuthController —
    // tapi decorator itu baru benar-benar berlaku setelah ThrottlerGuard
    // didaftarkan sebagai APP_GUARD global di bawah.
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 100,
      },
    ]),
    CommonModule,
    PrismaModule,
    UsersModule,
    AuthModule,
    StudentsModule,
    TeachersModule,
    SubjectsModule,
    TopicsModule,
    CompetenciesModule,
    DiagnosticsModule,
    AssessmentsModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    // Rate limiting dimatikan HANYA saat NODE_ENV=test -- limit produksi
    // (termasuk @Throttle 5/60s di AuthController) sama sekali tidak
    // berubah untuk environment lain. Tanpa ini, e2e test yang bikin
    // banyak akun (happy path, duplicate submission, security, dst dalam
    // satu run) akan kena 429 padahal bukan itu yang sedang diuji.
    ...(process.env.NODE_ENV === 'test'
      ? []
      : [
          {
            provide: APP_GUARD,
            useClass: ThrottlerGuard,
          },
        ]),
  ],
})
export class AppModule {}
