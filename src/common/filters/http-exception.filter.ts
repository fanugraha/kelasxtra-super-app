import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Response } from 'express';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    const isHttpException = exception instanceof HttpException;
    const status = isHttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const exceptionResponse = isHttpException ? exception.getResponse() : null;

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