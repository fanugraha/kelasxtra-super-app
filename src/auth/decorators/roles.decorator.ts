import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

// Contoh pemakaian di controller lain nanti:
// @Roles('ADMIN', 'TEACHER')
// @UseGuards(JwtAuthGuard, RolesGuard)
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);
