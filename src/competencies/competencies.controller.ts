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
import { CompetenciesService } from './competencies.service';
import { CreateCompetencyDto } from './dto/create-competency.dto';
import { UpdateCompetencyDto } from './dto/update-competency.dto';
import { ListCompetenciesDto } from './dto/list-competencies.dto';

@Controller('competencies')
@UseGuards(JwtAuthGuard, RolesGuard)
export class CompetenciesController {
  constructor(private competenciesService: CompetenciesService) {}

  @Get()
  async findAll(@Query() query: ListCompetenciesDto) {
    const competencies = await this.competenciesService.findAll(query);
    return { success: true, data: competencies, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const competency = await this.competenciesService.findOne(id);
    return { success: true, data: competency, message: 'Success' };
  }

  @Post()
  @Roles('ADMIN')
  async create(@Body() dto: CreateCompetencyDto) {
    const competency = await this.competenciesService.create(dto);
    return {
      success: true,
      data: competency,
      message: 'Competency berhasil dibuat',
    };
  }

  @Put(':id')
  @Roles('ADMIN')
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateCompetencyDto,
  ) {
    const competency = await this.competenciesService.update(id, dto);
    return {
      success: true,
      data: competency,
      message: 'Competency berhasil diperbarui',
    };
  }
}
