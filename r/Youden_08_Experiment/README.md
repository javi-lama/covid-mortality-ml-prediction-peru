# Weighted Youden Index Experiment (w=0.8)

## Overview

This experiment compares weighted Youden index optimization (w=0.8) against standard Youden J (w=1.0) for COVID-19 mortality prediction threshold selection.

## Methodology

### Standard Youden Index (w=1.0)

```
J = Sensitivity + Specificity - 1
```

Maximizes the sum of sensitivity and specificity equally.

### Weighted Youden Index (w=0.8)

```
J_w = Sensitivity + (Specificity * w) - 1
```

Where w=0.8 reduces the contribution of specificity by 20%, effectively favoring higher sensitivity (fewer false negatives) at the cost of lower specificity (more false positives).

### Clinical Rationale

In high-stakes medical screening (mortality prediction), missing deaths (false negatives) may be considered more costly than false alarms (false positives):

- **False Negative (missed death):** Patient doesn't receive needed intensive care, potentially fatal outcome
- **False Positive (false alarm):** Patient receives unnecessary monitoring, resource cost but safe outcome

A weight w < 1 reflects this asymmetric cost structure, prioritizing sensitivity over specificity.

## Data Sources

| File | Description |
|------|-------------|
| `roc_list_multimodel.rds` | Pre-computed pROC objects for all 4 models |
| `preds_list_multimodel.rds` | Prediction probabilities on test set |
| `data_testing.rds` | Test dataset (n=263, 42 deaths, 221 survivors) |

**Important:** This experiment uses existing ROC objects - no model retraining is performed. This ensures fair comparison between weighting schemes.

## Models Evaluated

1. **Random Forest** - Ensemble tree-based model
2. **XGBoost** - Gradient boosting model
3. **SVM-RBF** - Support Vector Machine with RBF kernel
4. **Logistic Regression** - Linear classification benchmark

## Output Files

### Tables

| File | Description |
|------|-------------|
| `Table_Youden_Comparison.csv` | Side-by-side w=1.0 vs w=0.8 metrics |
| `Table_Clinical_Impact.csv` | Deaths caught, missed, false alarms |
| `Table_Statistical_Tests.csv` | McNemar test for prediction differences |

### Figures

| File | Description |
|------|-------------|
| `Figure_Youden_Curves_4panel.png` | Youden curves for all 4 models |
| `Figure_SensSpec_Tradeoff.png` | Bar chart of Sensitivity/Specificity changes |

## Usage

```bash
# From project root directory
cd "/Users/javierlamaagurto/Documents/Research/Predicción Mortalidad COVID-19 ML/COVID-19_Mortality_Prediction_ML"

# Run the analysis
Rscript r/Youden_08_Experiment/Youden_08_Analysis.R

# Check outputs
ls -la results/youden_08/
```

## Expected Results

Based on preliminary analysis of the ROC curves:

| Model | Threshold (w=1.0) | Threshold (w=0.8) | Changed? |
|-------|-------------------|-------------------|----------|
| Random Forest | ~0.28 | ~0.22 | **YES** |
| XGBoost | ~0.17 | ~0.17 | NO |
| SVM-RBF | ~0.33 | ~0.33 | NO |
| Logistic Regression | ~0.08 | ~0.08 | NO |

### Key Finding

Only **Random Forest** shows sensitivity to the w=0.8 weighting. The other three models (XGBoost, SVM-RBF, Logistic Regression) produce identical thresholds for both w=1.0 and w=0.8.

**Interpretation:** This reveals that the shape of each model's ROC curve determines whether weighted optimization changes results. Models with "peaked" Youden curves have robust optima that don't shift with moderate weight changes, while models with "flatter" curves near the optimum may shift thresholds.

## Decision Framework

After running the experiment, evaluate each model against these criteria:

| Criterion | Threshold | Evidence |
|-----------|-----------|----------|
| Sensitivity improvement | ≥ 5 percentage points | Table_Youden_Comparison.csv |
| Specificity decrease | ≤ 10 percentage points | Table_Youden_Comparison.csv |
| NPV maintained | ≥ 0.95 | Table_Clinical_Impact.csv |
| Additional deaths caught | > 0 | Table_Clinical_Impact.csv |
| Statistical significance | p < 0.05 | Table_Statistical_Tests.csv |

## Technical Notes

### McNemar's Test

The McNemar test compares paired proportions:
- **b** = patients correctly classified by w=1.0 but not w=0.8
- **c** = patients correctly classified by w=0.8 but not w=1.0

If the test is significant (p < 0.05), the two thresholds produce meaningfully different classification performance.

### Why Not DeLong Test?

The DeLong test compares AUC values between models. Since changing the threshold does NOT change the ROC curve or AUC, DeLong tests are not applicable for comparing w=1.0 vs w=0.8 within the same model.

## Reproducibility

- **Seed:** 2026 (consistent with main analysis)
- **Dependencies:** tidymodels, tidyverse, pROC, patchwork, yardstick
- **Data:** Uses same train/test split as original model development

## Author

COVID-19 Mortality Prediction Project
Date: 2026-02-17
