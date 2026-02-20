# COVID-19 Mortality Risk Calculator: Project Map

## Project Overview

Machine learning system for predicting COVID-19 patient mortality using clinical admission data. Compares Random Forest, XGBoost, SVM-RBF, and Logistic Regression models.

**Key Findings:**
- Non-inferiority of ML vs LogReg (p=0.39)
- RF AUC: 0.86, LogReg AUC: 0.88
- NPV ≥0.98 across all models at optimal threshold

**Study:** 1,313 COVID-19 patients, 5 hospitals, 2020

---

## Quick Start

```bash
# Start full application (optimized, ~5 seconds)
./start_optimized.sh

# Frontend: http://localhost:5173
# API: http://localhost:8000
```

---

## Directory Structure

```
COVID-19_Mortality_Prediction_ML/
│
├── # CONFIGURATION & DOCS
├── CLAUDE.md                  # Project instructions for Claude Code
├── PROJECT_MAP.md             # This file - complete guide
├── PROJECT_INVENTORY.csv      # Full file manifest
├── DEPENDENCY_MAP.md          # Script dependency graph
│
├── # DEPLOYMENT
├── start_optimized.sh         # Fast startup script
├── start_app.sh               # Original startup script
│
├── # MODEL ARTIFACTS (at ROOT - do not move)
├── *.rds                      # 40 model/data files
│
├── data/                      # Raw data
│   └── database_gastrocovid_raw.csv
│
├── r/                         # R scripts
│   ├── 00_README.md           # Script guide
│   ├── core/                  # Data pipeline (run in order)
│   ├── models/                # Model training
│   ├── deployment/            # API scripts
│   ├── figures/               # Visualization
│   ├── experiments/           # Documented experiments
│   ├── testing/               # API tests
│   └── archive/               # Deprecated scripts
│
├── results/                   # Outputs
│   ├── publication/           # Current figures
│   ├── tables/                # CSV tables
│   │   ├── performance/       # Table 3, S1
│   │   └── odds_ratios/       # OR tables
│   ├── experiments/           # Experiment outputs
│   │   └── youden_08/
│   ├── documentation/         # Reports
│   └── archive/               # Old figures
│
├── web-app/                   # React frontend
│
└── backups/                   # Old backups
```

---

## Essential Files (18 Core)

### R Scripts (9)
1. `r/core/01_Data_Cleaning.R` - Data pipeline entry
2. `r/core/02_Preprocess.R` - Feature engineering
3. `r/core/03_Random_Forest.R` - RF training
4. `r/core/04_SHAP.R` - Explainability
5. `r/models/Multi_Model_Comparison.R` - Statistical comparison
6. `r/models/Model_Experiments.R` - XGBoost/SVM
7. `r/models/Logistic_Regression_GoldStandard.R` - Benchmark
8. `r/figures/Multi_Model_Figures.R` - Publication figures
9. `r/deployment/api_optimized.R` - Production API

### Model Artifacts (6)
10. `final_workflow_optimized.rds` - Production RF
11. `explainer_optimized.rds` - SHAP explainer
12. `modelo_rf_covid.rds` - Source RF
13. `model_logreg_goldstandard.rds` - Benchmark
14. `roc_list_multimodel.rds` - ROC curves
15. `top_8_validated_features.rds` - Feature set

### Data (3)
16. `data_cleaned.rds` - Cleaned data
17. `data_training.rds` - Training split
18. `data_testing.rds` - Test split

---

## Validated Features (Top 8)

1. `edad` - Age
2. `sexo` - Sex (hombre/mujer)
3. `severidad_sars` - COVID severity (Leve/Moderado/Severo)
4. `albumina` - Albumin (g/dL)
5. `plaquetas` - Platelet count (/uL)
6. `bilirrtotal` - Total bilirubin (mg/dL)
7. `sxingr_disnea` - Dyspnea symptom (TRUE/FALSE)
8. `sxingr_cefalea` - Headache symptom (TRUE/FALSE)

**Optimal Threshold:** 0.3184 (Youden index, 90% sensitivity target)

---

## Completed Experiments

| Experiment | Finding | Location |
|------------|---------|----------|
| Youden w=0.8 | Identical to w=1.0 | `r/experiments/Youden_08_Experiment/` |
| SMOTE Ratios | 0.8 marginal (+0.24% AUC) | `r/experiments/compare_smote_ratios.R` |
| CV Validation | No data leakage | `r/experiments/validate_cv_preprocessing.R` |
| Severity Ablation | -13.6% AUC without | `r/experiments/Random_Forest_No_Severidad.R` |

See `r/experiments/EXPERIMENTS_LOG.md` for details.

---

## Publication Figures

Located in `results/publication/`:
- `Figure_2_MultiModel_ROC.png` - ROC comparison
- `Figure_3_MultiModel_DCA.png` - Decision curve
- `Figure_4_Calibration_Panel.png` - Calibration
- `Figure_S1_AUC_Forest.png` - AUC forest
- `Figure_Lasso_CV_Path.png` - Feature selection
- `Poster_Fig1_ROC_MultiModel.png` - Poster ROC
- `Poster_Fig2_SHAP_Tornado.png` - Poster SHAP

---

## API Endpoints

**Base URL:** `http://localhost:8000`

### GET /health
Health check endpoint.

### POST /predict
Mortality risk prediction with SHAP explanation.

**Input:**
```json
{
  "edad": 65,
  "sexo": "hombre",
  "severidad_sars": "Severo",
  "albumina": 3.2,
  "plaquetas": 200000,
  "bilirrtotal": 1.5,
  "sxingr_disnea": true,
  "sxingr_cefalea": false
}
```

---

## Important Constraints

1. **DO NOT MOVE .rds files** from root - 15+ scripts depend on them
2. **Original scripts remain in r/** alongside organized copies
3. **API loads from ROOT** via path resolution
4. **web-app/ is React frontend** - separate deployment

---

## Version Information

- **Reorganization Date:** 2026-02-20
- **Git Tag:** `v1.0-pre-reorganization` (state before organization)
- **Backup Branch:** `backup/pre-reorganization-20260220`
