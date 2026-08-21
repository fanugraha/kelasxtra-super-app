import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { StudentsService } from './students.service';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { CreateGoalDto } from './dto/create-goal.dto';
import { UpdateGoalDto } from './dto/update-goal.dto';

@Controller('students')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('STUDENT')
export class StudentsController {
  constructor(private studentsService: StudentsService) {}

  @Get('me')
  async getMyProfile(@CurrentUser() user: { userId: number }) {
    const profile = await this.studentsService.getMyProfile(user.userId);
    return { success: true, data: profile, message: 'Success' };
  }

  @Put('me')
  async updateMyProfile(
    @CurrentUser() user: { userId: number },
    @Body() dto: UpdateProfileDto,
  ) {
    const profile = await this.studentsService.updateMyProfile(user.userId, dto);
    return { success: true, data: profile, message: 'Profil berhasil diperbarui' };
  }

  @Get('me/goals')
  async getMyGoals(@CurrentUser() user: { userId: number }) {
    const goals = await this.studentsService.getMyGoals(user.userId);
    return { success: true, data: goals, message: 'Success' };
  }

  @Post('me/goals')
  async createGoal(
    @CurrentUser() user: { userId: number },
    @Body() dto: CreateGoalDto,
  ) {
    const goal = await this.studentsService.createGoal(user.userId, dto);
    return { success: true, data: goal, message: 'Goal berhasil dibuat' };
  }

  @Put('me/goals/:id')
  async updateGoal(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateGoalDto,
  ) {
    const goal = await this.studentsService.updateGoal(user.userId, id, dto);
    return { success: true, data: goal, message: 'Goal berhasil diperbarui' };
  }

  @Get('me/competencies')
  async getMyCompetencies(@CurrentUser() user: { userId: number }) {
    const competencies = await this.studentsService.getMyCompetencies(user.userId);
    return { success: true, data: competencies, message: 'Success' };
  }

  @Get('me/learning-path')
  async getMyLearningPath(@CurrentUser() user: { userId: number }) {
    const path = await this.studentsService.getMyLearningPath(user.userId);
    return { success: true, data: path, message: 'Success' };
  }

  @Get('me/progress')
  async getMyProgress(@CurrentUser() user: { userId: number }) {
    const progress = await this.studentsService.getMyProgress(user.userId);
    return { success: true, data: progress, message: 'Success' };
  }
}
