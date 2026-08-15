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
import { SubjectsService } from './subjects.service';
import { CreateSubjectDto } from './dto/create-subject.dto';
import { UpdateSubjectDto } from './dto/update-subject.dto';
import { ListSubjectsDto } from './dto/list-subjects.dto';

@Controller('subjects')
@UseGuards(JwtAuthGuard, RolesGuard)
export class SubjectsController {
  constructor(private subjectsService: SubjectsService) {}

  // Semua role yang sudah login (STUDENT, TEACHER, ADMIN) boleh baca academic structure.
  @Get()
  async findAll(@Query() query: ListSubjectsDto) {
    const subjects = await this.subjectsService.findAll(query);
    return { success: true, data: subjects, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const subject = await this.subjectsService.findOne(id);
    return { success: true, data: subject, message: 'Success' };
  }

  // Hanya ADMIN yang boleh mengelola academic structure (lihat section 5.4).
  @Post()
  @Roles('ADMIN')
  async create(@Body() dto: CreateSubjectDto) {
    const subject = await this.subjectsService.create(dto);
    return { success: true, data: subject, message: 'Subject berhasil dibuat' };
  }

  @Put(':id')
  @Roles('ADMIN')
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateSubjectDto,
  ) {
    const subject = await this.subjectsService.update(id, dto);
    return {
      success: true,
      data: subject,
      message: 'Subject berhasil diperbarui',
    };
  }
}
