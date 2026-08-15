import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';
import { validateRequiredEnvVars } from './config/env.validation';

async function bootstrap() {
  // Section 15 dokumen master: aplikasi harus fail-fast kalau secret wajib
  // belum di-set, bukan diam-diam jalan dengan konfigurasi tidak lengkap.
  validateRequiredEnvVars();

  const app = await NestFactory.create(AppModule);

  // Secure HTTP headers (section 15). helmet() sebelumnya sudah jadi
  // dependency tapi belum pernah di-pasang.
  app.use(helmet());

  // CORS — fail closed: kalau CORS_ORIGIN kosong/tidak di-set, tidak ada
  // origin cross-site yang diizinkan sama sekali (section 15: "CORS hanya
  // mengizinkan origin yang diperlukan").
  const allowedOrigins = (process.env.CORS_ORIGIN ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  app.enableCors({
    origin: allowedOrigins,
    credentials: true,
  });

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

  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
