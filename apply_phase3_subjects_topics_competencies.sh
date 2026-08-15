#!/usr/bin/env bash
# apply_phase3_subjects_topics_competencies.sh
#
# KelasXtra backend (kelasxtra-super-app / education_app)
# Phase 3 lanjutan: Subjects, Topics, Competencies modules
# + fix seed.ts (role TEACHER hilang, tambah seed akun ADMIN)
# + main.ts: aktifkan transform di ValidationPipe (butuh utk query param angka)
#
# Idempotent — aman dijalankan berkali-kali, akan overwrite file dengan versi terbaru.
# Jalankan dari ROOT folder project backend (kelasxtra-super-app).

set -e

if [ ! -f "package.json" ] || [ ! -d "prisma" ]; then
  echo "Jalankan script ini dari root folder backend (kelasxtra-super-app), bukan dari folder lain."
  exit 1
fi

echo ">> Membuat folder module baru..."
mkdir -p src/subjects/dto src/topics/dto src/competencies/dto

echo ">> Menulis src/main.ts"
mkdir -p $(dirname src/main.ts)
cat > src/main.ts << 'FILEEOF'
import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );
  app.useGlobalInterceptors(new ResponseInterceptor());
  app.useGlobalFilters(new AllExceptionsFilter());

  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
FILEEOF

echo ">> Menulis src/app.module.ts"
mkdir -p $(dirname src/app.module.ts)
cat > src/app.module.ts << 'FILEEOF'
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './users/users.module';
import { AuthModule } from './auth/auth.module';
import { StudentsModule } from './students/students.module';
import { TeachersModule } from './teachers/teachers.module';
import { SubjectsModule } from './subjects/subjects.module';
import { TopicsModule } from './topics/topics.module';
import { CompetenciesModule } from './competencies/competencies.module';

@Module({
  imports: [
    PrismaModule,
    UsersModule,
    AuthModule,
    StudentsModule,
    TeachersModule,
    SubjectsModule,
    TopicsModule,
    CompetenciesModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
FILEEOF

echo ">> Menulis prisma/seed.ts"
mkdir -p $(dirname prisma/seed.ts)
cat > prisma/seed.ts << 'FILEEOF'
import { PrismaClient } from '../generated/prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import * as bcrypt from 'bcrypt';

const ADMIN_SEED_EMAIL = 'admin@kelasxtra.test';
const ADMIN_SEED_PASSWORD = 'admin12345';

async function runSeed() {
  const adapter = new PrismaMariaDb({
    host: 'localhost',
    port: 3306,
    user: 'root',
    password: process.env.DB_PASSWORD || 'qwerty123',
    database: 'education_app',
    connectionLimit: 5,
  });

  const prisma = new PrismaClient({ adapter });

  // TEACHER sempat ketinggalan dari list ini sebelumnya — itu penyebab
  // register role TEACHER gagal sampai dibuat manual lewat script terpisah.
  // Sekarang semua role yang dipakai di codebase (register + RBAC) sudah lengkap di sini.
  const roleNames = [
    'STUDENT',
    'TEACHER',
    'ADMIN',
    'PARENT',
    'TUTOR',
    'PROFESSIONAL',
  ];

  for (const roleName of roleNames) {
    await prisma.role.upsert({
      where: { name: roleName },
      update: {},
      create: { name: roleName },
    });
    console.log(`Role "${roleName}" siap.`);
  }

  // Belum ada endpoint publik untuk membuat akun ADMIN (memang sengaja,
  // demi keamanan), jadi satu akun admin awal disiapkan lewat seed ini
  // supaya endpoint admin-only (CRUD subjects/topics/competencies, dst.) bisa dites.
  const adminRole = await prisma.role.findUniqueOrThrow({
    where: { name: 'ADMIN' },
  });
  const existingAdmin = await prisma.user.findUnique({
    where: { email: ADMIN_SEED_EMAIL },
  });

  if (!existingAdmin) {
    const hashedPassword = await bcrypt.hash(ADMIN_SEED_PASSWORD, 10);
    await prisma.user.create({
      data: {
        email: ADMIN_SEED_EMAIL,
        password: hashedPassword,
        roleId: adminRole.id,
      },
    });
    console.log(
      `Akun ADMIN dibuat: ${ADMIN_SEED_EMAIL} / ${ADMIN_SEED_PASSWORD}`,
    );
  } else {
    console.log('Akun ADMIN seed sudah ada, tidak dibuat ulang.');
  }

  await prisma.$disconnect();
}

runSeed().catch((error) => {
  console.error('Gagal menjalankan seed:', error);
  process.exit(1);
});
FILEEOF

echo ">> Menulis src/subjects/subjects.module.ts"
mkdir -p $(dirname src/subjects/subjects.module.ts)
cat > src/subjects/subjects.module.ts << 'FILEEOF'
import { Module } from '@nestjs/common';
import { SubjectsController } from './subjects.controller';
import { SubjectsService } from './subjects.service';

@Module({
  controllers: [SubjectsController],
  providers: [SubjectsService],
  exports: [SubjectsService],
})
export class SubjectsModule {}
FILEEOF

echo ">> Menulis src/subjects/subjects.controller.ts"
mkdir -p $(dirname src/subjects/subjects.controller.ts)
cat > src/subjects/subjects.controller.ts << 'FILEEOF'
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
FILEEOF

echo ">> Menulis src/subjects/subjects.service.ts"
mkdir -p $(dirname src/subjects/subjects.service.ts)
cat > src/subjects/subjects.service.ts << 'FILEEOF'
import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateSubjectDto } from './dto/create-subject.dto';
import { UpdateSubjectDto } from './dto/update-subject.dto';
import { ListSubjectsDto } from './dto/list-subjects.dto';

@Injectable()
export class SubjectsService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListSubjectsDto) {
    return await this.prisma.subject.findMany({
      where: {
        status: query.includeInactive === 'true' ? undefined : 'ACTIVE',
        gradeLevel: query.gradeLevel,
      },
      orderBy: { name: 'asc' },
    });
  }

  async findOne(id: number) {
    const subject = await this.prisma.subject.findUnique({
      where: { id },
      include: { topics: { orderBy: { sequence: 'asc' } } },
    });

    if (!subject) {
      throw new NotFoundException('Subject tidak ditemukan.');
    }

    return subject;
  }

  async create(dto: CreateSubjectDto) {
    const existing = await this.prisma.subject.findUnique({
      where: { code: dto.code },
    });
    if (existing) {
      throw new ConflictException('Kode subject sudah digunakan.');
    }

    return this.prisma.subject.create({
      data: {
        code: dto.code,
        name: dto.name,
        gradeLevel: dto.gradeLevel,
        status: dto.status ?? 'ACTIVE',
      },
    });
  }

  async update(id: number, dto: UpdateSubjectDto) {
    await this.findOne(id);

    if (dto.code) {
      const existing = await this.prisma.subject.findUnique({
        where: { code: dto.code },
      });
      if (existing && existing.id !== id) {
        throw new ConflictException('Kode subject sudah digunakan.');
      }
    }

    return this.prisma.subject.update({
      where: { id },
      data: dto,
    });
  }
}
FILEEOF

echo ">> Menulis src/subjects/dto/create-subject.dto.ts"
mkdir -p $(dirname src/subjects/dto/create-subject.dto.ts)
cat > src/subjects/dto/create-subject.dto.ts << 'FILEEOF'
import { IsIn, IsOptional, IsString } from 'class-validator';

export class CreateSubjectDto {
  @IsString()
  code!: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;

  @IsOptional()
  @IsIn(['ACTIVE', 'INACTIVE'])
  status?: string;
}
FILEEOF

echo ">> Menulis src/subjects/dto/update-subject.dto.ts"
mkdir -p $(dirname src/subjects/dto/update-subject.dto.ts)
cat > src/subjects/dto/update-subject.dto.ts << 'FILEEOF'
import { IsIn, IsOptional, IsString } from 'class-validator';

export class UpdateSubjectDto {
  @IsOptional()
  @IsString()
  code?: string;

  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;

  @IsOptional()
  @IsIn(['ACTIVE', 'INACTIVE'])
  status?: string;
}
FILEEOF

echo ">> Menulis src/subjects/dto/list-subjects.dto.ts"
mkdir -p $(dirname src/subjects/dto/list-subjects.dto.ts)
cat > src/subjects/dto/list-subjects.dto.ts << 'FILEEOF'
import { IsIn, IsOptional, IsString } from 'class-validator';

export class ListSubjectsDto {
  // Default-nya cuma subject ACTIVE yang tampil (dipakai student/teacher).
  // Admin bisa kirim includeInactive=true untuk lihat semua termasuk yang INACTIVE.
  @IsOptional()
  @IsIn(['true', 'false'])
  includeInactive?: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;
}
FILEEOF

echo ">> Menulis src/topics/topics.module.ts"
mkdir -p $(dirname src/topics/topics.module.ts)
cat > src/topics/topics.module.ts << 'FILEEOF'
import { Module } from '@nestjs/common';
import { TopicsController } from './topics.controller';
import { TopicsService } from './topics.service';

@Module({
  controllers: [TopicsController],
  providers: [TopicsService],
  exports: [TopicsService],
})
export class TopicsModule {}
FILEEOF

echo ">> Menulis src/topics/topics.controller.ts"
mkdir -p $(dirname src/topics/topics.controller.ts)
cat > src/topics/topics.controller.ts << 'FILEEOF'
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
FILEEOF

echo ">> Menulis src/topics/topics.service.ts"
mkdir -p $(dirname src/topics/topics.service.ts)
cat > src/topics/topics.service.ts << 'FILEEOF'
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTopicDto } from './dto/create-topic.dto';
import { UpdateTopicDto } from './dto/update-topic.dto';
import { ListTopicsDto } from './dto/list-topics.dto';

@Injectable()
export class TopicsService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListTopicsDto) {
    return await this.prisma.topic.findMany({
      where: { subjectId: query.subjectId },
      orderBy: [{ subjectId: 'asc' }, { sequence: 'asc' }],
    });
  }

  async findOne(id: number) {
    const topic = await this.prisma.topic.findUnique({ where: { id } });

    if (!topic) {
      throw new NotFoundException('Topic tidak ditemukan.');
    }

    return topic;
  }

  private async ensureSubjectExists(subjectId: number) {
    const subject = await this.prisma.subject.findUnique({
      where: { id: subjectId },
    });
    if (!subject) {
      throw new NotFoundException('Subject untuk topic ini tidak ditemukan.');
    }
  }

  async create(dto: CreateTopicDto) {
    await this.ensureSubjectExists(dto.subjectId);

    return this.prisma.topic.create({
      data: {
        subjectId: dto.subjectId,
        name: dto.name,
        sequence: dto.sequence ?? 0,
      },
    });
  }

  async update(id: number, dto: UpdateTopicDto) {
    await this.findOne(id);

    return this.prisma.topic.update({
      where: { id },
      data: dto,
    });
  }
}
FILEEOF

echo ">> Menulis src/topics/dto/create-topic.dto.ts"
mkdir -p $(dirname src/topics/dto/create-topic.dto.ts)
cat > src/topics/dto/create-topic.dto.ts << 'FILEEOF'
import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateTopicDto {
  @IsInt()
  subjectId!: number;

  @IsString()
  name!: string;

  @IsOptional()
  @IsInt()
  sequence?: number;
}
FILEEOF

echo ">> Menulis src/topics/dto/update-topic.dto.ts"
mkdir -p $(dirname src/topics/dto/update-topic.dto.ts)
cat > src/topics/dto/update-topic.dto.ts << 'FILEEOF'
import { IsInt, IsOptional, IsString } from 'class-validator';

export class UpdateTopicDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsInt()
  sequence?: number;
}
FILEEOF

echo ">> Menulis src/topics/dto/list-topics.dto.ts"
mkdir -p $(dirname src/topics/dto/list-topics.dto.ts)
cat > src/topics/dto/list-topics.dto.ts << 'FILEEOF'
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListTopicsDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;
}
FILEEOF

echo ">> Menulis src/competencies/competencies.module.ts"
mkdir -p $(dirname src/competencies/competencies.module.ts)
cat > src/competencies/competencies.module.ts << 'FILEEOF'
import { Module } from '@nestjs/common';
import { CompetenciesController } from './competencies.controller';
import { CompetenciesService } from './competencies.service';

@Module({
  controllers: [CompetenciesController],
  providers: [CompetenciesService],
  exports: [CompetenciesService],
})
export class CompetenciesModule {}
FILEEOF

echo ">> Menulis src/competencies/competencies.controller.ts"
mkdir -p $(dirname src/competencies/competencies.controller.ts)
cat > src/competencies/competencies.controller.ts << 'FILEEOF'
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
FILEEOF

echo ">> Menulis src/competencies/competencies.service.ts"
mkdir -p $(dirname src/competencies/competencies.service.ts)
cat > src/competencies/competencies.service.ts << 'FILEEOF'
import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCompetencyDto } from './dto/create-competency.dto';
import { UpdateCompetencyDto } from './dto/update-competency.dto';
import { ListCompetenciesDto } from './dto/list-competencies.dto';

@Injectable()
export class CompetenciesService {
  constructor(private prisma: PrismaService) {}

  async findAll(query: ListCompetenciesDto) {
    return await this.prisma.competency.findMany({
      where: {
        subjectId: query.subjectId,
        topicId: query.topicId,
      },
      orderBy: { code: 'asc' },
    });
  }

  async findOne(id: number) {
    const competency = await this.prisma.competency.findUnique({
      where: { id },
    });

    if (!competency) {
      throw new NotFoundException('Competency tidak ditemukan.');
    }

    return competency;
  }

  private async validateReferences(subjectId: number, topicId?: number) {
    const subject = await this.prisma.subject.findUnique({
      where: { id: subjectId },
    });
    if (!subject) {
      throw new NotFoundException(
        'Subject untuk competency ini tidak ditemukan.',
      );
    }

    if (topicId) {
      const topic = await this.prisma.topic.findUnique({
        where: { id: topicId },
      });
      if (!topic) {
        throw new NotFoundException(
          'Topic untuk competency ini tidak ditemukan.',
        );
      }
      // Topic harus benar-benar berada di bawah subject yang sama, biar konsisten.
      if (topic.subjectId !== subjectId) {
        throw new ConflictException(
          'Topic yang dipilih tidak berada di subject yang sama.',
        );
      }
    }
  }

  async create(dto: CreateCompetencyDto) {
    const existing = await this.prisma.competency.findUnique({
      where: { code: dto.code },
    });
    if (existing) {
      throw new ConflictException('Kode competency sudah digunakan.');
    }

    await this.validateReferences(dto.subjectId, dto.topicId);

    return this.prisma.competency.create({
      data: {
        subjectId: dto.subjectId,
        topicId: dto.topicId,
        code: dto.code,
        name: dto.name,
        gradeLevel: dto.gradeLevel,
      },
    });
  }

  async update(id: number, dto: UpdateCompetencyDto) {
    const competency = await this.findOne(id);

    if (dto.code) {
      const existing = await this.prisma.competency.findUnique({
        where: { code: dto.code },
      });
      if (existing && existing.id !== id) {
        throw new ConflictException('Kode competency sudah digunakan.');
      }
    }

    if (dto.topicId) {
      await this.validateReferences(competency.subjectId, dto.topicId);
    }

    return this.prisma.competency.update({
      where: { id },
      data: dto,
    });
  }
}
FILEEOF

echo ">> Menulis src/competencies/dto/create-competency.dto.ts"
mkdir -p $(dirname src/competencies/dto/create-competency.dto.ts)
cat > src/competencies/dto/create-competency.dto.ts << 'FILEEOF'
import { IsInt, IsOptional, IsString } from 'class-validator';

export class CreateCompetencyDto {
  @IsInt()
  subjectId!: number;

  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsString()
  code!: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;
}
FILEEOF

echo ">> Menulis src/competencies/dto/update-competency.dto.ts"
mkdir -p $(dirname src/competencies/dto/update-competency.dto.ts)
cat > src/competencies/dto/update-competency.dto.ts << 'FILEEOF'
import { IsInt, IsOptional, IsString } from 'class-validator';

export class UpdateCompetencyDto {
  @IsOptional()
  @IsInt()
  topicId?: number;

  @IsOptional()
  @IsString()
  code?: string;

  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  gradeLevel?: string;
}
FILEEOF

echo ">> Menulis src/competencies/dto/list-competencies.dto.ts"
mkdir -p $(dirname src/competencies/dto/list-competencies.dto.ts)
cat > src/competencies/dto/list-competencies.dto.ts << 'FILEEOF'
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListCompetenciesDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subjectId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  topicId?: number;
}
FILEEOF


echo ""
echo ">> Semua file berhasil ditulis."
echo ""
echo "Langkah selanjutnya:"
echo "1. Generate ulang Prisma client (schema tidak berubah, tapi aman dijalankan): npx prisma generate"
echo "2. Jalankan seed lagi supaya role TEACHER lengkap + akun ADMIN dibuat:"
echo "   npx prisma db seed"
echo "   (atau: npx tsx prisma/seed.ts)"
echo "3. Restart server: npm run start:dev"
echo "4. Login sebagai admin@kelasxtra.test / admin12345 lalu tes endpoint:"
echo "   POST /api/v1/subjects   (ADMIN only)"
echo "   GET  /api/v1/subjects   (semua role login)"
echo "   POST /api/v1/topics     (ADMIN only)"
echo "   POST /api/v1/competencies (ADMIN only)"
