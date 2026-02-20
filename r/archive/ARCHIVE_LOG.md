# Archived Scripts Log

Scripts moved to archive on 2026-02-20 during project reorganization.

## Deprecated Scripts

### Logistic_Regression_GoldStandard_v2.R
- **Archived:** 2026-02-20
- **Reason:** Superseded by `Logistic_Regression_Parsimonious.R`
- **Originally:** Firth-corrected logistic regression with all features
- **Superseded by:** Parsimonious model uses 8 validated features with better EPV

### Logistic_Regression_Parsimonious_v2.R
- **Archived:** 2026-02-20
- **Reason:** Experimental variant, v1 is the production version
- **Originally:** Alternative feature selection approach
- **Superseded by:** `Logistic_Regression_Parsimonious.R` (v1)

### Poster_Figures_Reshape.R
- **Archived:** 2026-02-20
- **Reason:** Superseded by definitive version
- **Originally:** Data reshaping for poster figures
- **Superseded by:** `Poster_Figures_DEFINITIVE.R`

### Univariate_Analysis.R
- **Archived:** 2026-02-20
- **Reason:** Initial exploratory analysis, no longer needed
- **Originally:** Normality testing, variable classification
- **Status:** Analysis complete, findings incorporated into preprocessing

### Bivariate_Analysis.R
- **Archived:** 2026-02-20
- **Reason:** Initial exploratory analysis, no longer needed
- **Originally:** Association analysis with mortality
- **Status:** Analysis complete, findings in publication tables

### Statistical_Precision_Parameters.R
- **Archived:** 2026-02-20
- **Reason:** Functionality merged into Multi_Model_Comparison.R
- **Originally:** ROC-AUC CI, DeLong tests, Youden optimization
- **Superseded by:** `Multi_Model_Comparison.R` (comprehensive)

### Visualizations.R
- **Archived:** 2026-02-20
- **Reason:** Initial visualization script, superseded
- **Originally:** Early poster figures (Jan 10 versions)
- **Superseded by:** `Multi_Model_Figures.R`, `Poster_Figures_DEFINITIVE.R`

### Web_App.R
- **Archived:** 2026-02-20
- **Reason:** Replaced by React frontend
- **Originally:** Shiny app prototype
- **Superseded by:** `web-app/` React/TypeScript frontend

### Comparison_DCA_LogReg.R
- **Archived:** 2026-02-20
- **Reason:** Limited scope comparison
- **Originally:** Single RF vs LogReg DCA comparison
- **Superseded by:** `Multi_Model_Comparison.R` (4-model comparison)

## Restoration

To restore any archived script:
```bash
cp r/archive/ScriptName.R r/
```

All scripts are preserved with original functionality intact.
