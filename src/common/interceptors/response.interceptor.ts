import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export interface ApiResponse<T> {
  success: true;
  data: T;
  message: string;
}

@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, ApiResponse<T>> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<ApiResponse<T>> {
    return next.handle().pipe(
      map((result) => {
        // Kalau controller sudah manual return { success, data, message },
        // jangan dibungkus dua kali — pass through apa adanya.
        if (result && typeof result === 'object' && 'success' in result) {
          return result;
        }

        return {
          success: true,
          data: result ?? null,
          message: 'Success',
        };
      }),
    );
  }
}