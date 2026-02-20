# R Scripts Directory

## Directory Structure

```
r/
├── core/           # Core data pipeline (run in order)
├── models/         # Model training and comparison
├── deployment/     # API and production scripts
├── figures/        # Figure generation
├── experiments/    # Documented experiments
├── testing/        # API testing
└── archive/        # Deprecated scripts
```

## Execution Order

### Full Pipeline Rebuild

```r
# 1. Data Cleaning
source("r/core/01_Data_Cleaning.R")

# 2. Preprocessing & Feature Engineering
source("r/core/02_Preprocess.R")

# 3. Train Random Forest
source("r/core/03_Random_Forest.R")

# 4. Train XGBoost & SVM
source("r/models/Model_Experiments.R")

# 5. SHAP Analysis
source("r/core/04_SHAP.R")

# 6. Logistic Regression Benchmark
source("r/models/Logistic_Regression_GoldStandard.R")

# 7. Multi-Model Comparison
source("r/models/Multi_Model_Comparison.R")

# 8. Generate Publication Figures
source("r/figures/Multi_Model_Figures.R")

# 9. Build API Artifacts (required for deployment)
source("r/deployment/build_artifacts.R")
```

### Quick Start (API Only)

```bash
# From project root
./start_optimized.sh
```

## Directory Details

### core/
Scripts that must run in sequence:
- `01_Data_Cleaning.R` - Raw data → `data_cleaned.rds`
- `02_Preprocess.R` - Cleaned data → train/test splits, recipe
- `03_Random_Forest.R` - Train RF model
- `04_SHAP.R` - SHAP explainability, feature validation

### models/
Model training and comparison:
- `Model_Experiments.R` - XGBoost, SVM training
- `Logistic_Regression_GoldStandard.R` - Benchmark LogReg
- `Logistic_Regression_Parsimonious.R` - 8-feature LogReg
- `Multi_Model_Comparison.R` - DeLong tests, AUC comparison

### deployment/
Production API:
- `api_optimized.R` - Fast Plumber API (<10s startup)
- `api.R` - Original API (5-10 min startup)
- `build_artifacts.R` - Generate optimized .rds files

### figures/
Publication-quality visualizations:
- `Multi_Model_Figures.R` - ROC, DCA, calibration, forest
- `Poster_Figures_DEFINITIVE.R` - Conference poster figures

### experiments/
Documented experiments with findings:
- `Youden_08_Experiment/` - Weighted Youden index (w=0.8)
- `compare_smote_ratios.R` - SMOTE ratio sensitivity
- `validate_cv_preprocessing.R` - CV isolation check
- `Random_Forest_No_Severidad.R` - Severity ablation

### testing/
API testing utilities:
- `test_api_predict.R` - Direct function testing
- `test_api_client.R` - HTTP client testing

### archive/
Deprecated scripts (preserved for reference):
- See `ARCHIVE_LOG.md` for deprecation reasons

## Important Notes

1. **All .rds artifacts are saved to ROOT directory** (not r/)
2. **Scripts use relative paths** - run from project root
3. **Original scripts remain in r/** alongside organized copies
4. **API depends on root-level .rds files** - do not move them
