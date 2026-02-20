# Experiments Log

Documentation of completed experiments and their findings.

---

## Experiment 1: Youden w=0.8 (Weighted Threshold Optimization)

**Date:** February 17, 2026
**Status:** COMPLETED
**Location:** `r/experiments/Youden_08_Experiment/`

### Objective
Test whether a sensitivity-weighted Youden index (w=0.8) provides clinically superior threshold selection compared to the standard balanced Youden (w=1.0).

### Method
- Applied weighted Youden formula: `J(w) = w × Sensitivity + (1-w) × Specificity`
- w=0.8 prioritizes sensitivity (catching deaths) over specificity
- Compared thresholds across RF, XGBoost, SVM, LogReg

### Finding
**Identical thresholds for 3/4 models.** RF threshold shifts but no clinical impact.

| Model | w=1.0 Threshold | w=0.8 Threshold | Sensitivity Change |
|-------|-----------------|-----------------|-------------------|
| RF    | 0.3184          | 0.2847          | +2.4%             |
| XGBoost | 0.2910        | 0.2910          | 0%                |
| SVM   | 0.3011          | 0.3011          | 0%                |
| LogReg | 0.2639         | 0.2639          | 0%                |

### Decision
Use standard Youden (w=1.0). The weighted approach provides no additional benefit for this dataset.

---

## Experiment 2: SMOTE Ratio Comparison

**Date:** February 4, 2026
**Status:** COMPLETED
**Location:** `r/experiments/compare_smote_ratios.R`

### Objective
Determine optimal SMOTE over_ratio for class imbalance handling.

### Method
- Tested over_ratio values: 0.5, 0.8, 1.0
- Measured AUC, sensitivity, specificity, Kappa
- 5-fold cross-validation

### Finding
**Ratio 0.8 provides +0.24% AUC improvement (0.8703 vs 0.8679).**

| Ratio | AUC    | Sensitivity | Specificity |
|-------|--------|-------------|-------------|
| 0.5   | 0.8612 | 0.881       | 0.709       |
| 0.8   | 0.8703 | 0.905       | 0.723       |
| 1.0   | 0.8679 | 0.893       | 0.718       |

### Decision
Keep ratio=1.0 for consistency across models. The 0.24% improvement is not clinically meaningful.

---

## Experiment 3: CV Preprocessing Validation

**Date:** February 4, 2026
**Status:** COMPLETED
**Location:** `r/experiments/validate_cv_preprocessing.R`

### Objective
Verify no data leakage in cross-validation preprocessing pipeline.

### Method
- Checked that normalization uses only training fold statistics
- Verified SMOTE applied only to training folds
- Compared fold-wise preprocessing to ensure isolation

### Finding
**Confirmed correct isolation. No data leakage detected.**

- Mean scaling factors: μ=0.0003, σ=0.9987 (expected ~0 and ~1)
- SMOTE applied independently per fold
- No test data contamination in preprocessing

### Decision
Pipeline is correctly implemented. Proceed with confidence.

---

## Experiment 4: Severity Ablation Study

**Date:** January 10, 2026
**Status:** COMPLETED
**Location:** `r/experiments/Random_Forest_No_Severidad.R`

### Objective
Quantify the contribution of `severidad_sars` variable to model performance.

### Method
- Trained RF model with identical hyperparameters
- Excluded `severidad_sars` from feature set
- Compared AUC, sensitivity, specificity

### Finding
**AUC drops from 0.874 to 0.755 (-13.6%).** Clinical judgment is indispensable.

| Metric      | With Severity | Without Severity | Change |
|-------------|---------------|------------------|--------|
| AUC         | 0.874         | 0.755            | -13.6% |
| Sensitivity | 0.905         | 0.786            | -13.1% |
| Specificity | 0.723         | 0.631            | -12.7% |

### Decision
Severity assessment is critical. The model complements but does not replace clinical judgment.

---

## Experiment 5: Logistic Regression Evolution

**Date:** February 16-17, 2026
**Status:** COMPLETED
**Location:** `r/models/Logistic_Regression_*.R`

### Objective
Develop optimal logistic regression benchmark for ML comparison.

### Method
Iterative refinement:
1. **Full-feature LASSO** (GoldStandard) - Address EPV crisis
2. **Firth correction** (v2) - Handle rare events/separation
3. **Parsimonious 8-feature** - Deployable minimal model

### Finding
**Parsimonious v1 with Firth correction is optimal.**

| Version | Features | EPV  | OR (Severity) | AUC  |
|---------|----------|------|---------------|------|
| GoldStandard | ~50 | 3.1 | 18.4 | 0.880 |
| Firth (v2) | ~50 | 3.1 | 22.1 | 0.882 |
| Parsimonious v1 | 8 | 18.7 | 25.79 | 0.878 |
| Parsimonious v2 | 8 | 18.7 | 24.3 | 0.876 |

### Decision
Use Parsimonious v1 for publication. Archive v2 as experimental.

---

## Summary Table

| Experiment | Key Finding | Impact |
|------------|-------------|--------|
| Youden w=0.8 | Identical to w=1.0 | Use standard Youden |
| SMOTE Ratios | 0.8 marginally better | Keep 1.0 for consistency |
| CV Validation | No leakage | Pipeline correct |
| Severity Ablation | -13.6% AUC without | Clinical input essential |
| LogReg Evolution | Parsimonious v1 optimal | Use 8-feature Firth |
