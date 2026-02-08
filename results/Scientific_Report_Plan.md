# COMPREHENSIVE SCIENTIFIC RESEARCH REPORT PLAN
## Predicción de Mortalidad Intrahospitalaria en Pacientes con COVID-19 basado en Machine Learning Interpretable Multi-Modelo

---

## CRITICAL AUDIT OF CURRENT CODEBASE (Pre-Report Assessment)

Before designing the report, I conducted a line-by-line review of all 14 R scripts. Below are the key findings organized by scientific impact:

### ✅ STRENGTHS CONFIRMED
1. **Proper CV isolation**: `validate_cv_preprocessing.R` confirms that tidymodels correctly re-preps the recipe within each fold (normalization, imputation, SMOTE are fold-specific). No data leakage.
2. **Stratified splitting**: 80/20 split with `strata = desenlace` preserves 16%/84% class ratio.
3. **SMOTE within recipe**: Placed AFTER all preprocessing, executed only on training folds — methodologically correct.
4. **SHAP direction fix**: The explicit `predict_function = predict_mortality` returning `.pred_Fallecido` prevents sign inversion. This is a critical fix.
5. **Multi-model architecture**: Three fundamentally different learning paradigms (RF = bagging, XGBoost = boosting, SVM-RBF = kernel-based) provide legitimate algorithmic diversity.
6. **Bootstrap stability**: 100-iteration bootstrap for feature stability is publication-quality validation.
7. **Ablation study**: Removing `severidad_sars` (AUC drops to ~0.755) provides strong evidence for the clinical severity variable.

### ⚠️ CRITICAL ISSUES REQUIRING CORRECTION

#### Issue 1: DeLong Test Contradiction
- `Statistical_Precision_Parameters.R` reports DeLong p = 0.9514 (RF vs LogReg).
- The abstract and poster claim RF "supera significativamente" to logistic regression.
- **Reality**: There is NO statistically significant difference between RF (AUC 0.874) and LogReg (AUC 0.871). The wording must change to "comparable performance" or "non-inferior."
- **Impact**: This is the single most critical scientific integrity issue.

#### Issue 2: Missing XGBoost/SVM Test-Set Metrics
- `Model_Experiments.R` only reports `roc_auc` for XGBoost and SVM on the test set via `last_fit()`.
- Missing: sensitivity, specificity, PPV, NPV, Brier Score, PR-AUC at optimized thresholds.
- Missing: Confidence intervals for XGBoost and SVM AUC (no bootstrap CI computed).
- Missing: DeLong pairwise tests (RF vs XGB, RF vs SVM, XGB vs SVM).

#### Issue 3: Calibration Assessment Incomplete
- `Statistical_Precision_Parameters.R` only creates a visual calibration plot (10 bins).
- Missing: formal calibration metrics (Brier Score, calibration slope/intercept, Hosmer-Lemeshow or GND test).
- For all three models, not just RF.

#### Issue 4: PR-AUC Not Reported for Final Models
- PR-AUC is calculated during CV tuning (`metric_set(roc_auc, sensitivity, specificity, pr_auc)`) but never extracted for final test-set performance. For 16% prevalence, PR-AUC is more informative than ROC-AUC.

#### Issue 5: Renaming Bug in Data_Cleaning
- Lines in `Data_Cleaning_Organization.R` create a naming conflict:
  ```r
  med_carbapenem = dexametasona,  # WRONG: assigns dexametasona column to carbapenem
  med_dexam = dexametasona,       # DUPLICATE: same source column
  ```
- This means `med_carbapenem` and `med_dexam` are the SAME variable (both dexametasona). The actual `carbapenem` column data was lost.
- Later fixed with `med_carbapenem = carbapenem` but the original rename already destroyed the mapping.
- **Impact**: Needs verification. If `carbapenem` was the original column name before renaming, the second rename may have fixed it. But this is ambiguous and should be audited.

#### Issue 6: Traditional Scores Comparison (CHOSEN, CALL, HA2T2, ANDC)
- The abstract claims comparison against 4 traditional scores (AUC promedio 0.695).
- No R script implements these scores. This comparison was likely done externally or manually.
- **Must be codified in an R script for reproducibility.**

### 📋 GAPS REQUIRING NEW CODE/ANALYSIS

| Priority | Gap | Script Needed | Rationale |
|----------|-----|---------------|-----------|
| **P1** | Multi-model test-set metrics table | `Multi_Model_Comparison.R` | Core results table for paper |
| **P1** | Bootstrap 95% CI for XGB and SVM AUC | Same script | Statistical rigor |
| **P1** | DeLong pairwise tests (all model pairs) | Same script | Statistical comparison |
| **P1** | Brier Score for all models | Same script | Calibration quality metric |
| **P1** | PR-AUC for all models on test set | Same script | Critical for imbalanced data |
| **P2** | Calibration slope + intercept | `Calibration_Analysis.R` | Formal calibration assessment |
| **P2** | Multi-model ROC overlay figure | `Multi_Model_Figures.R` | Key figure for paper |
| **P2** | Multi-model DCA overlay | Same script | Clinical utility comparison |
| **P2** | Multi-model calibration plots | Same script | Visual calibration comparison |
| **P2** | CONSORT-style patient flow diagram | Manual/Figure | Required for observational studies |
| **P3** | Net Reclassification Index (NRI) | `Reclassification_Analysis.R` | Advanced comparison metric |
| **P3** | Traditional scores implementation | `Traditional_Scores.R` | Reproducibility of external comparison |
| **P3** | Learning curves | `Learning_Curves.R` | Assess data sufficiency |

---

## PROPOSED REPORT STRUCTURE

### Title
**"Multi-Model Explainable Machine Learning for In-Hospital COVID-19 Mortality Prediction: A Multicenter Retrospective Study in Peruvian Population"**

---

### 1. BACKGROUND (Antecedentes)

#### 1.1 Clinical Problem
- Peru: highest per-capita COVID-19 mortality worldwide (excess mortality > 600 per 100,000)
- Critical need for early risk stratification in resource-limited settings
- Existing validated scores (CHOSEN, CALL, HA₂T₂, ANDC) developed in non-Latin American populations
- Gap: No locally validated ML prediction model for Peruvian COVID-19 patients

#### 1.2 Rationale for ML over Traditional Scores
- Traditional scores use linear combinations of few variables → miss non-linear interactions
- ML captures complex feature interactions (e.g., albumin × severity × age)
- Ensemble methods (RF, XGBoost) handle missing data and class imbalance more robustly
- SHAP values provide individual-level explanations → clinician trust and actionable insights

#### 1.3 Current Evidence Gap
- Most ML COVID-19 mortality models: Chinese, European, or US populations
- Minimal representation of Latin American, resource-limited healthcare systems
- No multi-model comparison with interpretability in Peruvian cohorts
- Phase 2 novelty: Cross-model consensus feature selection with bootstrap validation

#### Key References to Include:
- Wynants et al. (2020) BMJ – Systematic review of COVID-19 prediction models
- Estiri et al. (2021) – ML for COVID-19 mortality (US VA system)
- Lundberg & Lee (2017) NeurIPS – SHAP values
- Biecek & Burzykowski (2021) – Explanatory Model Analysis
- Collins et al. (2024) TRIPOD+AI guidelines

---

### 2. OBJECTIVES (Objetivos)

#### Primary Objective
To develop, internally validate, and compare three explainable machine learning models (Random Forest, XGBoost, SVM-RBF) for predicting in-hospital mortality in Peruvian COVID-19 patients.

#### Secondary Objectives
1. To evaluate the discriminative performance (AUC, sensitivity, specificity, NPV, PPV, PR-AUC) and calibration (Brier Score, calibration slope) of each model against a logistic regression benchmark.
2. To identify and validate the most important predictive features using cross-model consensus SHAP analysis with bootstrap stability.
3. To assess clinical utility through decision curve analysis (DCA) and characterize model failure modes (false negative phenotyping).
4. To perform an ablation study evaluating the contribution of clinical severity assessment to model performance.

---

### 3. METHODS (Métodos)

#### 3.1 Study Design and Population
- **Design**: Multicenter retrospective observational cohort study
- **Setting**: 5 public hospitals in Peru (names to be specified)
- **Period**: January–December 2020
- **Population**: 1,313 adult patients hospitalized with confirmed COVID-19 (RT-PCR or antigen positive)
- **Outcome**: In-hospital mortality (binary: deceased vs. survived)
- **Mortality rate**: 210/1,313 (16.0%)
- **Ethical approval**: [Committee and approval number]
- **Reporting guideline**: TRIPOD+AI Statement

#### 3.2 Variables
**Predictor domains (54 variables after cleaning):**
- Demographics: age, sex, weight, height, BMI
- Comorbidities: DM, hypertension, dyslipidemia, cardiopathy, smoking, obesity, viral hepatitis, GERD, peptic ulcer, fatty liver, cirrhosis, HIV, cancer, pregnancy, TB, CKD (16 variables)
- Self-medication: hydroxychloroquine, azithromycin/ceftriaxone, corticosteroids, paracetamol, ivermectin, enoxaparin, fluoroquinolones (7 variables)
- Admission symptoms: fever, sore throat, odynophagia, cough, chest pain, headache, fatigue, anosmia, dyspnea, altered sensorium, dysgeusia, nausea/vomiting, GER, dysphagia, abdominal pain, diarrhea, jaundice, GI bleeding (18 variables)
- Admission laboratory: AST (TGO), ALT (TGP), total bilirubin, albumin, INR, alkaline phosphatase, platelets (7 variables)
- Clinical severity: SARS severity classification (Mild/Moderate/Severe) — ordered factor
- **Engineered features**: hepatic ratio (bilirubin/albumin), log-platelets

**Outcome**: `desenlace` (Fallecido/Vivo)

#### 3.3 Data Preprocessing Pipeline
1. **Data cleaning** (`Data_Cleaning_Organization.R`):
   - Removed 1,000 empty rows (artifact of CSV export)
   - Type conversion (73 variables recoded to logical, numeric, factor)
   - Biologically implausible values (lab = 0) → NA
   - Height outliers (cm → m conversion)
   - INR outlier correction (10.0 → 1.0)
   - BMI recalculation from cleaned weight/height
   - GGT dropped (>58% missing, exceeding 15% threshold)
   
2. **Feature engineering** (`Random_Forest_Preprocess.R`):
   - KNN imputation (k=5) for numeric predictors
   - Mode imputation for categorical predictors
   - Hepatic ratio: bilirubin_total / (albumin + 0.1)
   - Log-platelets: log(platelets + 1)
   - Collinearity removal: Spearman r > 0.60 threshold (removed: peso [r=0.885 with IMC], TGO [r=0.811 with TGP])
   - Near-zero variance filtering
   - Yeo-Johnson transformation for normality
   - Z-score normalization
   - One-hot encoding for nominal predictors
   - SMOTE oversampling (over_ratio = 1.0, k = 5) → balanced 882:882

3. **Data split**: 80/20 stratified by outcome → Training: 1,050 | Testing: 263

4. **Preprocessing isolation validation** (`validate_cv_preprocessing.R`):
   - Confirmed: normalization computed per-fold (mean ≈ 0, SD ≈ 1 within each fold)
   - Confirmed: imputation uses fold-specific statistics
   - Confirmed: SMOTE applied per-fold (balance ratio ≈ 1.0 per fold)
   - Conclusion: No data leakage in CV estimates

#### 3.4 Model Development

**3.4.1 Random Forest** (`Random_Forest.R`)
- Engine: ranger (impurity-based importance)
- Hyperparameter grid: mtry ∈ [2,20] (10 levels) × min_n ∈ [5,40] (5 levels) = 50 combinations
- Trees: 1,000
- Tuning: 5-fold stratified CV, optimizing ROC-AUC
- Selection: `select_best()` on ROC-AUC

**3.4.2 Gradient Boosted Trees (XGBoost)** (`Model_Experiments.R`)
- Engine: xgboost
- Hyperparameter space (6 dimensions): tree_depth [3,10], min_n [5,30], loss_reduction [0,5], sample_size [0.6,1.0], mtry (adaptive), learn_rate [0.01,0.3]
- Grid: Latin hypercube, 40 combinations
- Trees: 1,000
- Tuning: 5-fold stratified CV, optimizing ROC-AUC

**3.4.3 Support Vector Machine (SVM-RBF)** (`Model_Experiments.R`)
- Engine: kernlab (radial basis function kernel)
- Hyperparameter space: cost [0.01,100] (log₁₀ scale) × rbf_sigma [0.001,0.316] (log₁₀ scale)
- Grid: Regular 7×7 = 49 combinations
- Tuning: 5-fold stratified CV, optimizing ROC-AUC

**3.4.4 Logistic Regression Benchmark** (`Comparison_DCA_LogReg.R`)
- Engine: glm (standard maximum likelihood)
- Same imputation and normalization as ML models
- No SMOTE (baseline comparison without resampling)
- No hyperparameter tuning

**All models used the identical master recipe** (`rf_recipe_master.rds`) to ensure apples-to-apples comparison.

#### 3.5 Threshold Optimization
- Method: Youden's J index maximization on ROC curve
- Optimal threshold: 0.3184 (shifted from default 0.50)
- Clinical rationale: High-sensitivity strategy for mortality screening (prioritize catching deaths over avoiding false alarms)

#### 3.6 Model Evaluation

**Discrimination metrics** (on held-out test set, n=263):
- ROC-AUC with 95% CI (bootstrap, B=2000)
- PR-AUC (precision-recall, critical for 16% prevalence)
- Sensitivity, Specificity, PPV, NPV at optimized threshold
- Cohen's κ

**Calibration metrics**:
- Brier Score
- Calibration plot (10-bin observed vs. predicted)
- Calibration slope and intercept (pending)

**Statistical comparison**:
- DeLong test for pairwise AUC differences (all 6 pairs)
- 95% CI for all diagnostic parameters (bootstrap, B=2000)

**Clinical utility**:
- Decision Curve Analysis (net benefit across threshold range 0–50%)

#### 3.7 Explainability Framework (SHAP Analysis)

**Global interpretability** (`SHAP.R`):
- Model-agnostic SHAP values (Shapley additive explanations) computed via DALEX/DALEXtra
- Computed for RF, XGBoost, and SVM on entire test set
- Explainer configured with explicit `predict_function` returning `.pred_Fallecido` to ensure correct directionality

**Cross-model consensus**:
- Mean |SHAP| per variable per model → variable ranking
- Spearman correlation of RF vs. XGBoost rankings
- Consensus score: mean rank across models

**Bootstrap feature stability**:
- 100 bootstrap iterations of training data
- RF (500 trees, mtry=10, min_n=20) fitted per bootstrap
- Top-10 features recorded per iteration
- Stability criterion: ≥80% appearance frequency

**Top-8 feature selection criteria**:
1. Consensus top-10 rank (RF + XGBoost)
2. Bootstrap stability ≥ 80%
3. Rank consistency ≥ 0.75

**Local interpretability**:
- Waterfall plots for archetype cases:
  - True Positive (high-risk detected, pred > 0.80)
  - True Negative (low-risk survivor, pred < 0.10)
  - False Negative ("silent phenotype," deceased with pred < 0.20)
- Partial Dependence Plots for age and albumin

#### 3.8 Ablation Study
- Removed `severidad_sars` from recipe → retrained RF with same best hyperparameters
- Evaluated on same test set with `last_fit()`
- Purpose: Quantify the contribution of clinician's severity assessment vs. objective lab/demographic data alone

#### 3.9 SMOTE Ratio Sensitivity Analysis (`compare_smote_ratios.R`)
- Tested over_ratio = {0.5, 0.6, 0.7, 0.8, 1.0}
- 5-fold CV with fixed RF (trees=500, mtry=10, min_n=20)
- Metrics: ROC-AUC, sensitivity, specificity, accuracy, κ
- Result: over_ratio = 0.8 showed +0.24% AUC improvement (marginal)

#### 3.10 Software and Reproducibility
- R version 4.x with tidymodels framework
- Key packages: ranger, xgboost, kernlab, DALEX, DALEXtra, pROC, dcurves, probably, themis
- All seeds: set.seed(2026) for reproducibility
- Parallel computing: physical cores – 1

---

### 4. RESULTS (Resultados)

#### 4.1 Study Population (Table 1)
- N = 1,313 patients
- Age: 57 ± 15 years
- Sex: 67.4% male
- BMI: 26.8 [24.7–30.7]
- Mortality: 210 (16.0%)
- Severity: Mild 5.9%, Moderate 54.5%, Severe 39.5%
- Most common symptoms: dyspnea (89.3%), cough (72.9%), fever (71.5%), fatigue (65.1%)
- Key labs: albumin 3.3 ± 0.5, TGO 44.7 [28–80], platelets 230k [179k–331k]

#### 4.2 Bivariate Analysis (Table 2)
Significant associations with mortality (p < 0.05):
- Higher age (62 vs 56, p < 0.001)
- Dyslipidemia (28.6% vs 20.1%, p = 0.006)
- Obesity (36.2% vs 26.7%, p = 0.005)
- Fatty liver (29.0% vs 22.0%, p = 0.027)
- Cancer (5.2% vs 2.5%, p = 0.035)
- CKD (7.1% vs 2.9%, p = 0.002)
- Dyspnea (95.7% vs 88.1%, p = 0.001)
- Altered sensorium (22.9% vs 14.6%, p = 0.003)
- Lower albumin (3.1 vs 3.3, p < 0.001)
- Higher platelets (263k vs 224k, p = 0.036)
- Severe COVID (92.4% vs 29.5%, p < 0.001)

Protective associations:
- Sore throat (39.0% vs 51.6%, p < 0.001)
- Headache (27.6% vs 47.4%, p < 0.001)
- Anosmia (17.1% vs 25.3%, p = 0.011)
- Self-medication with paracetamol (19.0% vs 32.9%, p < 0.001)

#### 4.3 Model Performance Comparison (Table 3 — CORE RESULTS TABLE)

**This table needs to be GENERATED from new code. Expected structure:**

| Metric | Random Forest | XGBoost | SVM-RBF | Logistic Regression |
|--------|:---:|:---:|:---:|:---:|
| **ROC-AUC (95% CI)** | 0.874 (0.817–0.918) | [PENDING] | [PENDING] | 0.871 (0.837–0.901) |
| **PR-AUC** | [PENDING] | [PENDING] | [PENDING] | [PENDING] |
| **Brier Score** | [PENDING] | [PENDING] | [PENDING] | [PENDING] |
| **Sensitivity** | 0.90 (0.81–0.98) | [PENDING] | [PENDING] | [PENDING] |
| **Specificity** | 0.81 (0.74–0.87) | [PENDING] | [PENDING] | [PENDING] |
| **PPV** | [PENDING] | [PENDING] | [PENDING] | [PENDING] |
| **NPV** | 0.98 (0.95–0.99) | [PENDING] | [PENDING] | [PENDING] |
| **Cohen's κ** | [PENDING] | [PENDING] | [PENDING] | [PENDING] |
| **Optimal Threshold** | 0.318 | [PENDING] | [PENDING] | [PENDING] |

**DeLong Pairwise Comparisons (Table 3B):**

| Comparison | ΔAUC | Z statistic | p-value |
|------------|------|-------------|---------|
| RF vs LogReg | +0.003 | 0.061 | 0.951 |
| RF vs XGBoost | [PENDING] | [PENDING] | [PENDING] |
| RF vs SVM | [PENDING] | [PENDING] | [PENDING] |
| XGBoost vs SVM | [PENDING] | [PENDING] | [PENDING] |
| XGBoost vs LogReg | [PENDING] | [PENDING] | [PENDING] |
| SVM vs LogReg | [PENDING] | [PENDING] | [PENDING] |

#### 4.4 Hyperparameter Sensitivity
- RF: Best mtry = [from show_best], best min_n = [from show_best]
- XGBoost: Top 5 configurations within [range] of best AUC → robust to parameter changes
- SVM: Cost and sigma sensitivity plots

#### 4.5 Feature Importance and Interpretability

**4.5.1 Cross-Model Consensus (Table 4)**

| Rank | Variable | RF Mean |SHAP| | XGB Mean |SHAP| | Consensus Rank | Bootstrap Stability |
|------|----------|---------|---------|----------------|---------------------|
| 1 | severidad_sars_Severo | [value] | [value] | [rank] | [%] |
| 2 | severidad_sars_Moderado | ... | ... | ... | ... |
| ... | ... | ... | ... | ... | ... |

- Feature ranking correlation (RF vs XGBoost): Spearman ρ = [value], p = [value]
- Interpretation: If ρ > 0.70 → rankings are concordant across architectures

**4.5.2 SHAP Directionality**
Top risk factors (positive SHAP → increases mortality):
- Clinical severity (Severe) — strongest predictor
- Dyspnea
- Nausea/vomiting

Top protective factors (negative SHAP → decreases mortality):
- Fever (suggests active immune response)
- Higher albumin (nutritional/inflammatory reserve)
- Headache (suggests milder neurological COVID phenotype)

**4.5.3 Partial Dependence**
- Age: Mortality risk increases non-linearly after ~60 years
- Albumin: Protective effect accelerates below ~3.0 g/dL (critical threshold)

#### 4.6 Clinical Utility (DCA)
- RF provides net clinical benefit above "treat all" strategy in the 10–45% threshold range
- [Pending: Multi-model DCA overlay]

#### 4.7 Ablation Study
- Full model (with severity): AUC = 0.874
- Without severity: AUC = 0.755
- ΔAUC = –0.119 (13.6% relative decrease)
- Interpretation: Clinician's severity assessment is indispensable; objective data alone is insufficient

#### 4.8 False Negative Analysis ("Silent Phenotype")
- Patients who died but received < 20% predicted risk
- Profile: moderate severity, normal-range labs, no dyspnea at admission
- Interpretation: Captures the non-linear, sudden deterioration characteristic of COVID-19
- Clinical implication: Even "low-risk" patients need monitoring protocols

#### 4.9 SMOTE Sensitivity
- Optimal ratio: 0.8 (AUC 0.8703 vs 1.0 baseline AUC 0.8679)
- Improvement: +0.24 percentage points (marginal, not clinically meaningful)
- Conclusion: Results are robust to SMOTE ratio choice

---

### 5. DISCUSSION (Discusión)

#### 5.1 Principal Findings
- Three ML architectures achieved comparable high discrimination (AUC ~0.87)
- RF and XGBoost showed the strongest performance; SVM-RBF [pending results]
- **Critical honesty**: RF did NOT statistically outperform logistic regression (DeLong p = 0.95). The advantage lies in interpretability (SHAP), not raw discrimination.
- The value proposition of ML is in INTERPRETABILITY and INDIVIDUAL-LEVEL EXPLANATIONS, not necessarily in aggregate AUC superiority

#### 5.2 Comparison with Literature
- Our AUC (0.874) is competitive with international benchmarks:
  - Estiri et al. (2021): AUC 0.91 (US VA, larger sample, different features)
  - Li et al. (2020): AUC 0.87 (China, XGBoost)
  - Vaid et al. (2020): AUC 0.89 (Mount Sinai, multi-model)
- Traditional scores in our population (AUC ~0.695) significantly underperformed → validates need for locally adapted models
- First multi-model interpretable study in Peruvian population

#### 5.3 Clinical Implications
1. **High NPV (0.98)**: "If the model says low risk, trust it" → safe discharge/de-escalation tool
2. **Threshold at 31.8%**: Shifts from 50% default → high-sensitivity screening strategy
3. **Severity is essential**: The ablation study proves that clinical judgment cannot be replaced by labs alone
4. **Silent phenotype**: Identifies a subgroup that evades prediction → need for monitoring protocols

#### 5.4 Methodological Strengths
1. TRIPOD+AI-compliant reporting
2. Multi-model approach reduces algorithm-specific bias
3. Cross-model SHAP consensus provides robust feature selection
4. Bootstrap stability validates feature importance robustness
5. CV preprocessing isolation verified (no data leakage)
6. SMOTE sensitivity analysis confirms robustness to resampling choices

#### 5.5 Limitations
1. **Internal validation only**: No external cohort validation. Temporal and geographic generalizability unknown.
2. **Single time period (2020)**: Pre-vaccination, pre-Delta/Omicron variants. Applicability to current COVID landscape is limited.
3. **Retrospective design**: Susceptible to information bias and missing data patterns.
4. **Class imbalance**: Despite SMOTE, 16% mortality rate limits positive predictive value.
5. **Missing GGT**: Dropped due to >58% missingness — potential information loss.
6. **No external traditional scores code**: Comparison against CHOSEN/CALL/HA₂T₂/ANDC should be reproduced in code.
7. **RF vs LogReg not significantly different**: Limits claim of ML superiority in pure discrimination terms.
8. **No temporal validation**: Split is random, not temporal. A temporal split (train on early 2020, test on late 2020) would be more robust.

---

### 6. CONCLUSIONS (Conclusiones)

1. A multi-model explainable ML framework (RF, XGBoost, SVM) achieves high discriminative performance (AUC 0.874) for predicting in-hospital COVID-19 mortality in Peruvian patients.
2. Cross-model consensus SHAP analysis, validated by bootstrap stability, identifies clinical severity, dyspnea, albumin, and age as the most consistent predictors across algorithmic paradigms.
3. The model's high negative predictive value (0.98) positions it as a safe triage tool for identifying low-risk patients in resource-limited settings.
4. Clinical severity assessment by the treating physician remains indispensable (AUC drops 13.6% without it), demonstrating that ML augments, but does not replace, clinical judgment.
5. False negative analysis reveals a "silent phenotype" of patients with moderate severity and normal labs who deteriorate suddenly, warranting continued monitoring protocols.

---

## PROPOSED FIGURES AND TABLES

### Tables

| Table | Content | Status |
|-------|---------|--------|
| **Table 1** | Univariate characteristics (demographics, comorbidities, symptoms, labs) | ✅ EXISTS (tbl_1_export.docx) |
| **Table 2** | Bivariate analysis by mortality with p-values | ✅ EXISTS (tbl_2_export.docx) |
| **Table 3** | Multi-model performance comparison (AUC, Sens, Spec, PPV, NPV, PR-AUC, Brier, κ) with 95% CI | ❌ NEEDS CREATION |
| **Table 3B** | DeLong pairwise comparison matrix | ❌ NEEDS CREATION |
| **Table 4** | Hyperparameter search spaces and best configurations per model | ❌ NEEDS CREATION |
| **Table 5** | Top-8 consensus features with SHAP values, ranks, bootstrap stability % | ❌ NEEDS CREATION |
| **Table 6** | Ablation study: performance with/without severity | ❌ NEEDS CREATION |

### Figures

| Figure | Content | Status |
|--------|---------|--------|
| **Fig 1** | CONSORT-style patient flow diagram | ❌ NEEDS CREATION |
| **Fig 2** | Multi-model ROC curve overlay (RF, XGB, SVM, LogReg) with AUCs in legend | ❌ NEEDS CREATION |
| **Fig 3** | Multi-model DCA overlay | ❌ NEEDS CREATION |
| **Fig 4** | Calibration plots (paneled: RF, XGB, SVM) | ❌ NEEDS CREATION |
| **Fig 5A** | SHAP global bar chart (RF) – Top 15 variables | ✅ EXISTS (Figure_SHAP_RF.png) |
| **Fig 5B** | SHAP global bar chart (XGBoost) – Top 15 variables | ✅ EXISTS (Figure_SHAP_XGBoost.png) |
| **Fig 6** | Consensus feature importance with bootstrap stability (combined) | ✅ EXISTS (Figure_FINAL_Top8_Variables.png) |
| **Fig 7** | Confusion matrix (optimized threshold) – RF | ✅ EXISTS (Figure1_ConfusionMatrix_Opt.png) |
| **Fig 8** | Waterfall SHAP plots: TP, TN, FN comparison | ✅ PARTIALLY EXISTS |
| **Fig 9** | PDP for age and albumin | ✅ EXISTS (generated in SHAP.R) |
| **Fig 10** | Bootstrap stability plot | ✅ EXISTS (Figure_Bootstrap_Stability.png) |
| **Fig 11** | Hyperparameter sensitivity plots (XGB, SVM) | ✅ EXISTS |
| **Supp Fig 1** | SMOTE ratio sensitivity analysis | ✅ EXISTS |
| **Supp Fig 2** | Probability density distributions (Fallecido vs Vivo) | ✅ EXISTS |
| **Supp Fig 3** | Variable importance (ablation model without severity) | ✅ EXISTS |

---

## PRIORITY ACTION PLAN FOR CONTEST SUBMISSION

### Phase A: Generate Missing Statistical Results (HIGH PRIORITY)
Create `Multi_Model_Comparison.R` that:
1. Loads all 3 fitted models + LogReg
2. Generates predictions on test set
3. Computes: AUC (bootstrap CI), PR-AUC, Brier Score, Sens/Spec/PPV/NPV at Youden threshold for each
4. Runs DeLong pairwise tests for all 6 model pairs
5. Outputs Table 3 and Table 3B as formatted outputs

### Phase B: Generate Missing Figures (HIGH PRIORITY)
Create `Multi_Model_Figures.R` that:
1. Multi-model ROC overlay
2. Multi-model DCA overlay
3. Paneled calibration plots
4. Forest plot of AUCs with 95% CI

### Phase C: Draft Contest Deliverables
1. **Abstract** (≤ 3,000 characters): Restructured with corrected claims (remove "significantly superior to LogReg")
2. **Poster** (1920×1080 vertical): Redesigned with multi-model results and corrected SHAP figures
3. **Video script** (8 min): Structured presentation narrative

### Phase D: Supplementary Analyses (MEDIUM PRIORITY)
1. Formal calibration metrics
2. NRI/IDI if time permits
3. Traditional scores codification

---

## LANGUAGE NOTE FOR CONTEST
All deliverables (abstract, poster, video) should be in **Spanish** per APJ contest requirements.
The full scientific report should be in **English** for eventual Q1 journal submission, with Spanish translations for local contest.

---

*Report plan prepared: 2026-02-07*
*Next step: Generate Multi_Model_Comparison.R to fill pending metrics before drafting deliverables.*
