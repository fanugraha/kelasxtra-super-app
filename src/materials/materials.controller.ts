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
import { MaterialsService } from './materials.service';
import { CreateMaterialDto } from './dto/create-material.dto';
import { UpdateMaterialDto } from './dto/update-material.dto';
import { ListMaterialsDto } from './dto/list-materials.dto';

@Controller('materials')
@UseGuards(JwtAuthGuard, RolesGuard)
export class MaterialsController {
  constructor(private materialsService: MaterialsService) {}

  @Get()
  async findAll(@Query() query: ListMaterialsDto) {
    const materials = await this.materialsService.findAll(query);
    return { success: true, data: materials, message: 'Success' };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const material = await this.materialsService.findOne(id);
    return { success: true, data: material, message: 'Success' };
  }

  @Post()
  @Roles('TEACHER')
  async create(@CurrentUser() user: { userId: number }, @Body() dto: CreateMaterialDto) {
    const material = await this.materialsService.create(user.userId, dto);
    return { success: true, data: material, message: 'Learning material berhasil dibuat' };
  }

  @Put(':id')
  @Roles('TEACHER')
  async update(
    @CurrentUser() user: { userId: number },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateMaterialDto,
  ) {
    const material = await this.materialsService.update(user.userId, id, dto);
    return { success: true, data: material, message: 'Learning material berhasil diperbarui' };
  }
}
