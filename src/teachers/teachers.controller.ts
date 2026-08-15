import { Body, Controller, Get, Put, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { TeachersService } from './teachers.service';
import { UpdateTeacherProfileDto } from './dto/update-profile.dto';

@Controller('teachers')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('TEACHER')
export class TeachersController {
  constructor(private teachersService: TeachersService) {}

  @Get('me')
  async getMyProfile(@CurrentUser() user: { userId: number }) {
    const profile = await this.teachersService.getMyProfile(user.userId);
    return { success: true, data: profile, message: 'Success' };
  }

  @Put('me')
  async updateMyProfile(
    @CurrentUser() user: { userId: number },
    @Body() dto: UpdateTeacherProfileDto,
  ) {
    const profile = await this.teachersService.updateMyProfile(user.userId, dto);
    return { success: true, data: profile, message: 'Profil berhasil diperbarui' };
  }
}
