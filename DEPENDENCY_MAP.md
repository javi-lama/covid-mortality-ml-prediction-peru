# COVID-19 ML Project: Dependency Map

## Critical Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DATA PIPELINE                                       │
└─────────────────────────────────────────────────────────────────────────────┘

data/database_gastrocovid_raw.csv
         │
         ▼
┌────────────────────────────────┐
│ r/core/01_Data_Cleaning.R      │
│ (Data_Cleaning_Organization.R) │
│                                │
│ OUTPUT: data_cleaned.rds       │
└────────────────────────────────┘
         │
         ▼
┌────────────────────────────────┐
│ r/core/02_Preprocess.R         │
│ (Random_Forest_Preprocess.R)   │
│                                │
│ OUTPUTS:                       │
│   ├─ data_training.rds         │
│   ├─ data_testing.rds          │
│   ├─ data_split.rds            │
│   ├─ data_model_ready.rds      │
│   └─ rf_recipe_master.rds      │
└────────────────────────────────┘
         │
    ┌────┴────────────────────────────────────────┐
    │                    │                        │
    ▼                    ▼                        ▼
┌────────────────┐  ┌────────────────┐  ┌──────────────────────┐
│r/core/         │  │r/models/       │  │r/models/             │
│03_Random_      │  │Model_          │  │Logistic_Regression_  │
│Forest.R        │  │Experiments.R   │  │GoldStandard.R        │
│                │  │                │  │                      │
│ OUTPUT:        │  │ OUTPUTS:       │  │ OUTPUTS:             │
│ (workflow in   │  │ ├─model_       │  │ ├─model_logreg_      │
│  session)      │  │ │ xgboost_     │  │ │ goldstandard.rds   │
│                │  │ │ fit.rds      │  │ ├─model_logreg_      │
│                │  │ └─model_       │  │ │ lasso.rds          │
│                │  │   svm_fit.rds  │  │ └─threshold_         │
│                │  │                │  │   logreg_cv.rds      │
└────────────────┘  └────────────────┘  └──────────────────────┘
         │                    │                        │
         └────────────────────┼────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           r/core/04_SHAP.R                                   │
│                                                                              │
│ INPUTS:                                                                      │
│   ├─ data_testing.rds, data_training.rds, rf_recipe_master.rds              │
│   ├─ model_xgboost_fit.rds, model_svm_fit.rds                               │
│   └─ (workflow from 03_Random_Forest.R session)                              │
│                                                                              │
│ OUTPUTS:                                                                     │
│   ├─ modelo_rf_covid.rds                                                     │
│   ├─ top_8_validated_features.rds                                            │
│   └─ Figure_SHAP_*.png (archived)                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   r/models/Multi_Model_Comparison.R                          │
│                                                                              │
│ INPUTS:                                                                      │
│   ├─ modelo_rf_covid.rds                                                     │
│   ├─ model_xgboost_fit.rds, model_svm_fit.rds                               │
│   ├─ preds_logreg_goldstandard.rds, roc_logreg_goldstandard.rds (optional)  │
│   └─ data_testing.rds, data_training.rds, rf_recipe_master.rds              │
│                                                                              │
│ OUTPUTS:                                                                     │
│   ├─ roc_list_multimodel.rds                                                 │
│   ├─ preds_list_multimodel.rds                                               │
│   ├─ auc_results_multimodel.rds                                              │
│   ├─ model_logreg_fit.rds                                                    │
│   └─ Table_3*.csv                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     r/figures/Multi_Model_Figures.R                          │
│                                                                              │
│ INPUTS:                                                                      │
│   ├─ roc_list_multimodel.rds                                                 │
│   ├─ preds_list_multimodel.rds                                               │
│   └─ auc_results_multimodel.rds                                              │
│                                                                              │
│ OUTPUTS:                                                                     │
│   ├─ Figure_2_MultiModel_ROC.png                                             │
│   ├─ Figure_3_MultiModel_DCA.png                                             │
│   ├─ Figure_4_Calibration_Panel.png                                          │
│   └─ Figure_S1_AUC_Forest.png                                                │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                      DEPLOYMENT PIPELINE                                     │
└─────────────────────────────────────────────────────────────────────────────┘

modelo_rf_covid.rds + data_training.rds + data_testing.rds
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     r/deployment/build_artifacts.R                           │
│                                                                              │
│ OUTPUTS (saved to ROOT):                                                     │
│   ├─ final_workflow_optimized.rds      ─┐                                    │
│   ├─ explainer_optimized.rds           ─┼─ REQUIRED BY api_optimized.R       │
│   ├─ patient_template.rds              ─┤                                    │
│   ├─ df_training_cached.rds            ─┘                                    │
│   └─ df_testing_cached.rds                                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   r/deployment/api_optimized.R (PRODUCTION)                  │
│                                                                              │
│ LOADS FROM ROOT:                                                             │
│   ├─ final_workflow_optimized.rds                                            │
│   ├─ explainer_optimized.rds                                                 │
│   ├─ patient_template.rds                                                    │
│   └─ df_training_cached.rds                                                  │
│                                                                              │
│ ENDPOINTS:                                                                   │
│   ├─ GET /health                                                             │
│   └─ POST /predict                                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          start_optimized.sh                                  │
│                                                                              │
│ CHECKS:                                                                      │
│   - Verifies all required .rds files exist at ROOT                           │
│   - Runs build_artifacts.R if missing                                        │
│   - Starts Plumber API on port 8000                                          │
│   - Starts Vite frontend on port 5173                                        │
└─────────────────────────────────────────────────────────────────────────────┘


## File Dependencies Summary

### Files Used by Multiple Scripts (CRITICAL - DO NOT MOVE)

| File | Used By |
|------|---------|
| `data_training.rds` | Random_Forest.R, SHAP.R, Multi_Model_Comparison.R, Model_Experiments.R, Logistic_Regression_*.R, build_artifacts.R |
| `data_testing.rds` | Random_Forest.R, SHAP.R, Multi_Model_Comparison.R, Multi_Model_Figures.R, build_artifacts.R |
| `rf_recipe_master.rds` | Random_Forest.R, SHAP.R, Multi_Model_Comparison.R, Model_Experiments.R |
| `modelo_rf_covid.rds` | SHAP.R, Multi_Model_Comparison.R, build_artifacts.R |
| `roc_list_multimodel.rds` | Multi_Model_Figures.R, Poster_Figures_DEFINITIVE.R, Youden_08_Analysis.R |
| `model_xgboost_fit.rds` | SHAP.R, Multi_Model_Comparison.R |
| `model_svm_fit.rds` | SHAP.R, Multi_Model_Comparison.R |

### Entry Point Scripts (Run Independently)

| Script | Purpose | Prerequisites |
|--------|---------|---------------|
| `r/core/01_Data_Cleaning.R` | Initial data cleaning | Raw CSV data |
| `start_optimized.sh` | Start full application | All .rds artifacts |
| `r/deployment/build_artifacts.R` | Generate deployment files | Core model artifacts |

### Output-Only Scripts (No Downstream Dependencies)

- `r/figures/Multi_Model_Figures.R` → PNG figures only
- `r/figures/Poster_Figures_DEFINITIVE.R` → PNG figures only
- `r/experiments/Youden_08_Analysis.R` → Experiment results only

## Execution Order for Full Pipeline

```
1. r/core/01_Data_Cleaning.R
   └─→ Creates: data_cleaned.rds

2. r/core/02_Preprocess.R
   └─→ Creates: data_training.rds, data_testing.rds, rf_recipe_master.rds

3. r/core/03_Random_Forest.R
   └─→ Creates: (workflow in session)

4. r/models/Model_Experiments.R
   └─→ Creates: model_xgboost_fit.rds, model_svm_fit.rds

5. r/core/04_SHAP.R
   └─→ Creates: modelo_rf_covid.rds, top_8_validated_features.rds

6. r/models/Logistic_Regression_GoldStandard.R
   └─→ Creates: model_logreg_goldstandard.rds, logreg_*.rds

7. r/models/Multi_Model_Comparison.R
   └─→ Creates: roc_list_multimodel.rds, preds_list_multimodel.rds, auc_results_multimodel.rds

8. r/figures/Multi_Model_Figures.R
   └─→ Creates: Figure_2/3/4/S1_*.png

9. r/deployment/build_artifacts.R
   └─→ Creates: final_workflow_optimized.rds, explainer_optimized.rds, patient_template.rds
```

## API Artifact Path Resolution

```r
# api_optimized.R line 47
base_path <- if (file.exists("final_workflow_optimized.rds")) "." else ".."
```

**Critical:** API loads from ROOT directory. Artifacts MUST stay at root.
