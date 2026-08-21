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
import { CoursesService } from './courses.service';
import { CreateCourseDto } from './dto/create-course.dto';
import { UpdateCourseDto } from './dto/update-course.dto';
import { ListCoursesDto } from './dto/list-courses.dto';

@Controller('courses')
@UseGuards(JwtAuthGuard, RolesGuard)
export class CoursesController {
  constructor(private coursesService: CoursesService) {}

  @Get()
  async findAll(@Query() query: ListCoursesDto) {
    const courses = await this.coursesService.findAll(query);
    return { success: true, data: courses, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const course = await this.coursesService.findOne(id);
    return { success: true, data: course, message: 'Success' };
  }

  // Course dibuat & dikelola TEACHER saja (bukan ADMIN) -- Course.teacherId
  // wajib diisi di schema dan ADMIN tidak punya TeacherProfile, jadi
  // secara desain course selalu punya pemilik teacher yang jelas.
  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateCourseDto) {
    const course = await this.coursesService.create(user.userId, dto);
    return { success: true, data: course, message: 'Course berhasil dibuat' };
  }

  @Put(':id')
  @Roles('TEACHER')
  async update(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateCourseDto,
  ) {
    const course = await this.coursesService.update(user.userId, id, dto);
    return { success: true, data: course, message: 'Course berhasil diperbarui' };
  }
}
