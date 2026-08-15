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
import { TopicsService } from './topics.service';
import { CreateTopicDto } from './dto/create-topic.dto';
import { UpdateTopicDto } from './dto/update-topic.dto';
import { ListTopicsDto } from './dto/list-topics.dto';

@Controller('topics')
@UseGuards(JwtAuthGuard, RolesGuard)
export class TopicsController {
  constructor(private topicsService: TopicsService) {}

  @Get()
  async findAll(@Query() query: ListTopicsDto) {
    const topics = await this.topicsService.findAll(query);
    return { success: true, data: topics, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const topic = await this.topicsService.findOne(id);
    return { success: true, data: topic, message: 'Success' };
  }

  @Post()
  @Roles('ADMIN')
  async create(@Body() dto: CreateTopicDto) {
    const topic = await this.topicsService.create(dto);
    return { success: true, data: topic, message: 'Topic berhasil dibuat' };
  }

  @Put(':id')
  @Roles('ADMIN')
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateTopicDto,
  ) {
    const topic = await this.topicsService.update(id, dto);
    return { success: true, data: topic, message: 'Topic berhasil diperbarui' };
  }
}
