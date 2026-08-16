import { Module } from '@nestjs/common';
import { EvidenceService } from './evidence/evidence.service';
import { CompetencySnapshotService } from './snapshots/competency-snapshot.service';
import { LearningEngineConfigService } from './config/learning-engine-config.service';
import { MasteryService } from './mastery/mastery.service';
import { LearningPathReconciler } from './learning-path/learning-path-reconciler';

// Diagnostic & Assessment module import module ini, lalu pakai service-service
// ini (plus fungsi murni dari mastery-calculator/confidence-calculator/
// mastery-classifier) untuk memproses submission tanpa duplikasi logic.
@Module({
  providers: [
    EvidenceService,
    CompetencySnapshotService,
    LearningEngineConfigService,
    MasteryService,
    LearningPathReconciler,
  ],
  exports: [
    EvidenceService,
    CompetencySnapshotService,
    LearningEngineConfigService,
    MasteryService,
    LearningPathReconciler,
  ],
})
export class LearningEngineModule {}
