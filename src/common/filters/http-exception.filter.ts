import {
  ArgumentsHost,
  Catch,
  ConflictException,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Response } from 'express';
import { Prisma } from '../../../generated/prisma/client';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    // Race condition pada uniqueness check (findUnique lalu create) bisa
    // lolos pengecekan aplikasi tapi tetap gagal di level MySQL unique
    // constraint. Tanpa ini, error itu jatuh ke cabang 500 generic di bawah
    // padahal seharusnya 409 Conflict — berlaku otomatis untuk semua module
    // (subjects, competencies, topics, dst.), bukan cuma yang sudah
    // ditangani manual per-service.
    const normalizedException =
      exception instanceof Prisma.PrismaClientKnownRequestError && exception.code === 'P2002'
        ? new ConflictException('Data dengan nilai unik ini sudah ada.')
        : exception;

    const isHttpException = normalizedException instanceof HttpException;
    const status = isHttpException
      ? normalizedException.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const exceptionResponse = isHttpException ? normalizedException.getResponse() : null;

    let message: string;
    let errors: string[] = [];

    if (typeof exceptionResponse === 'string') {
      message = exceptionResponse;
    } else if (exceptionResponse && typeof exceptionResponse === 'object') {
      const body = exceptionResponse as { message?: string | string[] };
      if (Array.isArray(body.message)) {
        // Ini kasus error dari ValidationPipe (array of validation messages)
        message = 'Validation failed';
        errors = body.message;
      } else {
        message = body.message ?? 'Internal server error';
      }
    } else {
      message = 'Internal server error';
    }

    response.status(status).json({
      success: false,
      message,
      errors,
    });
  }
}
