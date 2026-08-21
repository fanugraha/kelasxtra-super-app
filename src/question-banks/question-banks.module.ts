import { Module } from '@nestjs/common';
import { QuestionBanksController } from './question-banks.controller';
import { QuestionBanksService } from './question-banks.service';

@Module({
  controllers: [QuestionBanksController],
  providers: [QuestionBanksService],
  exports: [QuestionBanksService],
})
export class QuestionBanksModule {}
