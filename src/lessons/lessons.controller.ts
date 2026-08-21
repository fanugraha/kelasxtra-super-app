import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { LessonsService } from './lessons.service';
import { CreateLessonDto } from './dto/create-lesson.dto';
import { UpdateLessonDto } from './dto/update-lesson.dto';
import { ListLessonsDto } from './dto/list-lessons.dto';

@Controller('lessons')
@UseGuards(JwtAuthGuard, RolesGuard)
export class LessonsController {
  constructor(private lessonsService: LessonsService) {}

  @Get()
  async findAll(@Query() query: ListLessonsDto) {
    const lessons = await this.lessonsService.findAll(query);
    return { success: true, data: lessons, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const lesson = await this.lessonsService.findOne(id);
    return { success: true, data: lesson, message: 'Success' };
  }

  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateLessonDto) {
    const lesson = await this.lessonsService.create(user.userId, dto);
    return { success: true, data: lesson, message: 'Lesson berhasil dibuat' };
  }

  @Put(':id')
  @Roles('TEACHER')
  async update(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateLessonDto,
  ) {
    const lesson = await this.lessonsService.update(user.userId, id, dto);
    return { success: true, data: lesson, message: 'Lesson berhasil diperbarui' };
  }
}
