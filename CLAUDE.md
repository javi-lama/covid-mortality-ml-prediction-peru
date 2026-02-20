# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

COVID-19 Mortality Risk Calculator: A machine learning system for predicting COVID-19 patient mortality using clinical admission data. Consists of an R/Plumber API backend with SHAP explainability and a React/TypeScript frontend.

## Quick Start Commands

```bash
# Start full application (optimized, ~5 seconds startup)
./start_optimized.sh

# Start full application (original, 5-10 minutes startup - uses api.R)
./start_app.sh

# Build/rebuild model artifacts (required before first optimized start)
Rscript r/build_artifacts.R

# Frontend only (web-app directory)
cd web-app && npm run dev

# Frontend build
cd web-app && npm run build

# Frontend lint
cd web-app && npm run lint
```

## Architecture

### Backend (R/Plumber)

**API Endpoints:**
- `GET /health` - Health check
- `POST /predict` - Mortality risk prediction with SHAP explanation

**Key Files:**
- `r/api_optimized.R` - Fast-start API (loads pre-built .rds artifacts)
- `r/api.R` - Original API (sources training scripts on startup)
- `r/build_artifacts.R` - Generates .rds artifacts for optimized API

**Data Pipeline:**
1. `r/Data_Cleaning_Organization.R` - Raw data cleaning → `data_cleaned.rds`
2. `r/Random_Forest_Preprocess.R` - Feature engineering, train/test split, recipe creation
3. `r/Random_Forest.R` - Model training → `modelo_rf_covid.rds`
4. `r/SHAP.R` - SHAP explainability analysis

**Model Artifacts (root directory):**
- `final_workflow_optimized.rds` - Trained Random Forest workflow
- `explainer_optimized.rds` - DALEX explainer with SHAP background
- `patient_template.rds` - Column structure template for new patients
- `df_training_cached.rds` / `df_testing_cached.rds` - Cached data splits

### Frontend (React/TypeScript/Vite)

**Location:** `web-app/`

**Tech Stack:** React 19, TypeScript, Vite, Tailwind CSS, Framer Motion, Recharts, React Hook Form + Zod

**Structure:**
- `src/features/calculator/` - Patient input form (RiskForm)
- `src/features/results/` - Prediction display (ResultCard)
- `src/components/viz/` - SHAP visualization (SHAPBarChart)
- `src/api/client.ts` - API client for R backend

### Clinical Model Details

**Outcome:** Binary classification (Fallecido/Vivo - Deceased/Alive)

**Top 8 Validated Features:**
1. `edad` - Age
2. `sexo` - Sex (hombre/mujer)
3. `severidad_sars` - COVID severity (Leve/Moderado/Severo)
4. `albumina` - Albumin (g/dL)
5. `plaquetas` - Platelet count (/uL)
6. `bilirrtotal` - Total bilirubin (mg/dL)
7. `sxingr_disnea` - Dyspnea symptom (TRUE/FALSE)
8. `sxingr_cefalea` - Headache symptom (TRUE/FALSE)

**Optimal Threshold:** 0.3184 (optimized for 90% sensitivity via Youden index)

## R Dependencies

Core: tidymodels, tidyverse, DALEX, DALEXtra, plumber, themis, ranger

## Ports

- API: 8000
- Vite Dev: 5173
