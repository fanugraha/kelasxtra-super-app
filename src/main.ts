import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';
import { validateRequiredEnvVars } from './config/env.validation';

async function bootstrap() {
  // Wajib jalan SEBELUM app dibuat — kalau secret penting kosong, aplikasi
  // harus gagal start dengan pesan jelas, bukan baru error saat endpoint
  // pertama dipanggil di production.
  validateRequiredEnvVars();

  const app = await NestFactory.create(AppModule);

  app.use(helmet());

  // Fail closed: kalau CORS_ORIGIN tidak di-set, JANGAN default ke "izinkan
  // semua origin" — origin list kosong berarti tidak ada origin cross-site
  // yang diizinkan sampai eksplisit dikonfigurasi.
  const corsOrigins = (process.env.CORS_ORIGIN ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.enableCors({
    origin: corsOrigins.length > 0 ? corsOrigins : false,
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
bootstrap().catch((error) => {
  console.error('Gagal bootstrap aplikasi:', error);
  process.exit(1);
});
