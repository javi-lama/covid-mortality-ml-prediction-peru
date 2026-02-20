# Deployment Plan Audit Report
**Date:** February 7, 2026
**Auditor:** Claude Code (Senior Web App Developer Perspective)
**Subject:** Critical Review of Antigravity's Deployment Plan for COVID-19 Mortality Prediction Web App

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Antigravity's Original Plan](#antigravitys-original-plan)
3. [Critical Issues Identified](#critical-issues-identified)
4. [Security Vulnerability Analysis](#security-vulnerability-analysis)
5. [Improved Deployment Plan](#improved-deployment-plan)
6. [Corrected Dockerfile](#corrected-dockerfile)
7. [Security Fixes Required](#security-fixes-required)
8. [Cost Comparison](#cost-comparison)
9. [Implementation Checklist](#implementation-checklist)
10. [Files to Modify/Create](#files-to-modifycreate)

---

## Executive Summary

Antigravity's deployment plan demonstrates sound architectural thinking with the split frontend/backend approach, but contains **5 critical issues** that would prevent successful zero-cost deployment and compromise security and scientific rigor.

| Verdict | Category | Issues Found |
|---------|----------|--------------|
| **REJECT** | Cost | Railway has NO free tier (eliminated Aug 2023) |
| **REJECT** | Security | 4 critical vulnerabilities |
| **REJECT** | Dockerfile | Missing packages, no security hardening |
| **APPROVE** | Architecture | Split architecture is correct |
| **APPROVE** | Artifacts | Pre-compiled .rds approach is sound |

**Recommendation:** Do not proceed with antigravity's plan as-is. Implement the security fixes and platform changes outlined in this report before deployment.

---

## Antigravity's Original Plan

### Proposed Architecture
```
User (Clinician) --> HTTPS --> Vercel (React Frontend) --> POST /predict --> Railway (R Container)
```

### Proposed Dockerfile
```dockerfile
FROM rocker/r-ver:4.3.1
RUN apt-get update && apt-get install -y \
    libgomp1 libsodium-dev libcurl4-openssl-dev libssl-dev
RUN R -e "install.packages(c('plumber', 'tidymodels', 'DALEX', 'DALEXtra', 'ranger', 'xgboost', 'janitor', 'naniar'))"
WORKDIR /app
COPY final_workflow_optimized.rds explainer_optimized.rds patient_template.rds df_training_cached.rds api_optimized.R .
EXPOSE 8000
ENTRYPOINT ["R", "-e", "pr <- plumber::plumb('api_optimized.R'); pr$run(host='0.0.0.0', port=8000)"]
```

### Proposed Platforms
- **Frontend:** Vercel (Free Tier)
- **Backend:** Railway (~$5/month, claimed free tier exists)

### Claimed Benefits
- <10s latency using pre-compiled artifacts
- Global CDN via Vercel
- Docker containerization for reproducibility

---

## Critical Issues Identified

### Issue #1: CRITICAL - Railway Has No Free Tier

**Antigravity's Claim:**
> "Railway: ~$5/month... Free tiers exist but may sleep"

**Reality:**
Railway eliminated their free tier in August 2023. The minimum cost is $5/month with usage-based billing. This directly contradicts the requirement for zero cost.

**Evidence:** Railway's pricing page and multiple third-party comparisons confirm no free tier exists as of 2024-2026.

**Impact:** Deployment would incur $60+/year in costs.

**Correct Alternative:** Render.com
- 750 free hours/month (enough for showcase use)
- Docker support for R containers
- Auto-sleep after 15min inactivity (acceptable for demos)
- Health check integration
- Truly zero cost

---

### Issue #2: CRITICAL - Dockerfile Deficiencies

**Problems Found:**

| Issue | Severity | Impact |
|-------|----------|--------|
| Missing `tidyverse` package | HIGH | api_optimized.R line 29 uses tidyverse; API will crash |
| No non-root user | HIGH | Container runs as root; security vulnerability |
| No HEALTHCHECK directive | MEDIUM | Container orchestration can't detect failures |
| No .dockerignore | MEDIUM | Includes raw patient data in image |
| Using R 4.3.1 | LOW | Should use 4.3.2+ for better compatibility |
| No multi-stage or optimization | LOW | Image larger than necessary |

**Result:** The proposed Dockerfile would build but the API would fail on startup due to missing tidyverse.

---

### Issue #3: HIGH - Security Vulnerabilities (4 Found)

#### 3.1 CORS Wildcard
**Location:** `api_optimized.R:95`
```r
res$setHeader("Access-Control-Allow-Origin", "*")
```
**Risk:** Any malicious website can make requests to your API, potentially harvesting predictions or abusing the service.

**OWASP Classification:** A01:2021 - Broken Access Control

#### 3.2 No Rate Limiting
**Location:** API-wide (no implementation exists)

**Risk:**
- Denial of Service attacks
- API abuse/scraping
- Potential cost overruns on paid tiers

**OWASP Classification:** A05:2021 - Security Misconfiguration

#### 3.3 PHI in Logs
**Location:** `api_optimized.R:114-116`
```r
cat(sprintf("  Body: %s\n", substr(req$postBody, 1, 200)))
```
**Risk:** Patient health information (age, symptoms, lab values) written to logs. Violates HIPAA, GDPR, and data protection principles.

**OWASP Classification:** A09:2021 - Security Logging and Monitoring Failures

#### 3.4 No Backend Input Validation
**Location:** `/predict` endpoint

**Risk:**
- Malformed data crashes API
- Potential injection attacks
- Invalid clinical values produce meaningless predictions

**OWASP Classification:** A03:2021 - Injection

---

### Issue #4: MEDIUM - Scientific Reproducibility Gaps

| Missing Element | Impact | Recommendation |
|-----------------|--------|----------------|
| Model versioning | Cannot track which model version produced results | Add `model_card.yaml` |
| Root .gitignore | Risk of committing patient data to git | Create comprehensive .gitignore |
| Dependency pinning | Different package versions may produce different results | Pin all R package versions in Dockerfile |
| Seed documentation | SHAP results not fully reproducible | Document seed=2026 in model card |
| No audit trail | Cannot trace predictions to model state | Add request IDs and model version to responses |

---

### Issue #5: LOW - User Experience Concerns

**Cold Start Warning Missing:**

Free-tier containers (Render, Fly.io, etc.) sleep after 15 minutes of inactivity. The first request after sleep takes 30-60 seconds while the container restarts and R loads packages.

**Impact:** Users may think the app is broken and abandon it.

**Recommendation:** Add loading state with message:
> "Initializing prediction engine... This may take up to 60 seconds on first use."

---

## Security Vulnerability Analysis

### Current Security Posture

| Layer | Status | Details |
|-------|--------|---------|
| Transport | PARTIAL | HTTPS provided by platform, but no HSTS headers |
| Authentication | NONE | Public API, no keys or tokens |
| Authorization | NONE | All endpoints publicly accessible |
| Input Validation | FRONTEND ONLY | Zod validation on React, but backend trusts all input |
| Rate Limiting | NONE | Unlimited requests allowed |
| Logging | INSECURE | PHI written to logs |
| CORS | INSECURE | Wildcard allows all origins |

### Threat Model

| Threat | Likelihood | Impact | Current Mitigation |
|--------|------------|--------|-------------------|
| API abuse/scraping | HIGH | MEDIUM | NONE |
| DoS attack | MEDIUM | HIGH | NONE |
| Data exfiltration via logs | LOW | HIGH | NONE |
| CORS exploitation | MEDIUM | MEDIUM | NONE |
| Invalid input causing crashes | MEDIUM | LOW | Frontend validation only |

### Required Mitigations

1. **CORS Whitelist:** Only allow your frontend domain
2. **Rate Limiting:** 30 requests/minute/IP
3. **Input Validation:** Server-side clinical range checks
4. **Log Sanitization:** Remove PHI, hash IPs
5. **Request IDs:** Add X-Request-ID for tracing without exposing data

---

## Improved Deployment Plan

### Recommended Architecture

```
+-------------------+        HTTPS         +--------------------+
|  Cloudflare       | -------------------> |  Render.com        |
|  Pages            |                      |  Docker Container  |
|  (React Frontend) |   POST /predict      |  (R Plumber API)   |
+-------------------+                      +--------------------+
        |                                          |
   FREE (Unlimited                            FREE (750h/mo)
    bandwidth)                                 Auto-sleep
```

### Why This Architecture

1. **Cloudflare Pages** (Frontend)
   - Unlimited bandwidth (vs 100GB on Vercel/Netlify)
   - Global edge network with 300+ locations
   - Git-connected auto-deploys
   - Free SSL with HTTPS enforcement
   - Better DDoS protection than Vercel

2. **Render.com** (Backend)
   - Only viable free tier for Docker containers
   - 750 hours/month (enough for showcase use)
   - Native Docker support
   - Health check integration
   - Auto-sleep after 15min (acceptable for demos)

### Alternative: GitHub Codespaces Demo Mode

For live presentations or paper reviewers:
- Use GitHub Codespaces free tier (60 hours/month)
- Run both frontend and backend locally in Codespace
- Share via Codespace port forwarding
- No cold starts, instant response

---

## Corrected Dockerfile

```dockerfile
# ============================================================================
# COVID-19 Mortality Risk Calculator - Production Dockerfile
# Base: rocker/r-ver:4.3.2 (Debian-based, optimized for production)
# Version: 1.0.0
# ============================================================================

FROM rocker/r-ver:4.3.2

# Metadata
LABEL maintainer="research-team"
LABEL version="1.0.0"
LABEL description="COVID-19 Mortality Prediction API"

# System dependencies for R packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libsodium-dev \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install R packages in dependency order
# CRITICAL: ranger and tidyverse MUST be included
RUN R -e "install.packages(c( \
    'plumber', \
    'tidymodels', \
    'tidyverse', \
    'ranger', \
    'DALEX', \
    'DALEXtra', \
    'digest' \
), repos='https://cloud.r-project.org/', Ncpus=4)"

# Create non-root user for security (OWASP recommendation)
RUN useradd -m -u 1000 -s /bin/bash ruser

# Set working directory
WORKDIR /app

# Copy only required files (use .dockerignore for exclusions)
COPY --chown=ruser:ruser api_optimized.R .
COPY --chown=ruser:ruser final_workflow_optimized.rds .
COPY --chown=ruser:ruser explainer_optimized.rds .
COPY --chown=ruser:ruser patient_template.rds .
COPY --chown=ruser:ruser df_training_cached.rds .

# Switch to non-root user
USER ruser

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Expose port
EXPOSE 8000

# Start API with proper error handling
CMD ["R", "-e", "library(plumber); pr('api_optimized.R') |> pr_run(host='0.0.0.0', port=8000)"]
```

### Required .dockerignore

```dockerignore
# Data files - NEVER include in image
*.xlsx
*.csv
database_*.csv
BASE_FINAL_RAW.xlsx
data_cleaned.rds
data_model_ready.rds

# R artifacts
.RData
.RDataTmp*
.Rhistory
.Rproj.user/
*.Rproj

# Frontend (separate deployment)
web-app/

# Logs and temp files
*.log
*.pdf
Rplots.pdf

# IDE and OS
.vscode/
.idea/
.DS_Store

# Git
.git/
.gitignore

# Documentation (not needed in runtime)
*.md
Poster_*.png
Figure_*.png
FIGURA_*.png
```

---

## Security Fixes Required

### Fix 1: CORS Whitelist

**Replace in `api_optimized.R` (lines 93-106):**

```r
#* Enable CORS with domain restriction
#* @filter cors
cors <- function(req, res) {
  # Whitelist allowed origins - UPDATE THESE AFTER DEPLOYMENT
  allowed_origins <- c(
    "https://your-app.pages.dev",           # Cloudflare Pages production
    "https://covid-predictor.pages.dev",    # Alternative subdomain
    "http://localhost:5173",                 # Local development
    "http://localhost:3000"                  # Alternative local port
  )

  origin <- req$HTTP_ORIGIN
  if (!is.null(origin) && origin %in% allowed_origins) {
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Vary", "Origin")
  }

  res$setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Origin, X-Request-ID")
  res$setHeader("Access-Control-Max-Age", "86400")

  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }

  plumber::forward()
}
```

### Fix 2: Rate Limiting

**Add to `api_optimized.R` after the cors filter:**

```r
# In-memory rate limiter (suitable for single-instance deployment)
rate_limit_store <- new.env()

#* Rate limiting filter - 30 requests per minute per IP
#* @filter rate_limit
rate_limit <- function(req, res) {
  ip <- req$REMOTE_ADDR
  if (is.null(ip)) ip <- "unknown"

  current_time <- as.numeric(Sys.time())
  window <- 60  # 1 minute window
  max_requests <- 30

  # Get or initialize request history for this IP
  if (!exists(ip, envir = rate_limit_store)) {
    assign(ip, c(), envir = rate_limit_store)
  }

  # Clean old requests outside window
  requests <- get(ip, envir = rate_limit_store)
  requests <- requests[requests > (current_time - window)]

  # Check limit before adding new request
  if (length(requests) >= max_requests) {
    res$status <- 429
    res$setHeader("Retry-After", as.character(window))
    return(list(
      error = "Rate limit exceeded",
      message = "Maximum 30 requests per minute allowed",
      retry_after_seconds = window
    ))
  }

  # Add current request
  requests <- c(requests, current_time)
  assign(ip, requests, envir = rate_limit_store)

  plumber::forward()
}
```

### Fix 3: Sanitized Logging

**Replace the logging filter:**

```r
#* Request logging filter - SANITIZED (no PHI)
#* @filter logging
logging <- function(req, res) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Hash IP for privacy (can still correlate requests without exposing IP)
  ip_hash <- substr(digest::digest(paste0(req$REMOTE_ADDR, "salt-2026"), algo="sha256"), 1, 8)

  # Generate request ID for tracing
  request_id <- substr(digest::digest(paste0(timestamp, runif(1)), algo="md5"), 1, 12)
  res$setHeader("X-Request-ID", request_id)

  # Log only non-sensitive metadata
  cat(sprintf("[%s] [%s] %s %s from %s\n",
      timestamp,
      request_id,
      req$REQUEST_METHOD,
      req$PATH_INFO,
      ip_hash
  ))

  # Log request size only (NOT content) for debugging
  if (req$REQUEST_METHOD == "POST" && !is.null(req$postBody)) {
    cat(sprintf("  Request size: %d bytes\n", nchar(req$postBody)))
  }

  plumber::forward()
}
```

### Fix 4: Backend Input Validation

**Add at the beginning of the `/predict` endpoint:**

```r
#* @post /predict
function(edad, sexo, severidad_sars, albumina, plaquetas, bilirrtotal,
         sxingr_disnea, sxingr_cefalea, res) {

  # Input validation with clinical ranges
  errors <- c()

  # Age validation (18-120 years, clinical range)
  edad_num <- suppressWarnings(as.numeric(edad))
  if (is.na(edad_num) || edad_num < 18 || edad_num > 120) {
    errors <- c(errors, "Edad debe estar entre 18 y 120 anos")
  }

  # Albumin (1.0-6.0 g/dL, clinical range for COVID patients)
  albumina_num <- suppressWarnings(as.numeric(albumina))
  if (is.na(albumina_num) || albumina_num < 1.0 || albumina_num > 6.0) {
    errors <- c(errors, "Albumina debe estar entre 1.0 y 6.0 g/dL")
  }

  # Platelets (1,000-1,000,000 /uL)
  plaquetas_num <- suppressWarnings(as.numeric(plaquetas))
  if (is.na(plaquetas_num) || plaquetas_num < 1000 || plaquetas_num > 1000000) {
    errors <- c(errors, "Plaquetas deben estar entre 1,000 y 1,000,000 /uL")
  }

  # Bilirubin (0.1-20 mg/dL)
  bili_num <- suppressWarnings(as.numeric(bilirrtotal))
  if (is.na(bili_num) || bili_num < 0.1 || bili_num > 20) {
    errors <- c(errors, "Bilirrubina debe estar entre 0.1 y 20 mg/dL")
  }

  # Categorical validation (whitelist approach)
  if (!tolower(sexo) %in% c("hombre", "mujer")) {
    errors <- c(errors, "Sexo debe ser 'hombre' o 'mujer'")
  }

  if (!severidad_sars %in% c("Leve", "Moderado", "Severo")) {
    errors <- c(errors, "Severidad debe ser 'Leve', 'Moderado', o 'Severo'")
  }

  # Return validation errors
  if (length(errors) > 0) {
    res$status <- 400
    return(list(
      error = "Validation failed",
      message = "One or more input values are outside clinical ranges",
      details = errors
    ))
  }

  # ... rest of prediction logic continues ...
}
```

---

## Cost Comparison

| Component | Antigravity's Plan | Improved Plan | Savings |
|-----------|-------------------|---------------|---------|
| Frontend Hosting | Vercel Free | Cloudflare Pages Free | $0 (better bandwidth) |
| Backend Hosting | Railway $5/mo | Render.com Free | $60/year |
| SSL Certificate | Included | Included | $0 |
| Domain | Optional | Optional | $0-12/year |
| CDN | Vercel Edge | Cloudflare (300+ locations) | $0 (better coverage) |
| **Total Annual Cost** | **$60+** | **$0** | **$60+** |

### Platform Comparison for R Docker

| Platform | Free Tier | Docker Support | Cold Start | RAM Limit | Verdict |
|----------|-----------|----------------|------------|-----------|---------|
| **Render.com** | 750h/mo | Yes | 30-60s | 512MB | RECOMMENDED |
| Railway | NONE | Yes | N/A | N/A | REJECTED (no free tier) |
| Fly.io | $5 credit | Yes | 10-30s | 256MB | Credit exhausts quickly |
| Google Cloud Run | Limited | Yes | 10-20s | 256MB | Complex setup |
| Heroku | NONE | Via buildpack | N/A | N/A | REJECTED (no free tier) |

---

## Implementation Checklist

### Phase 1: Security Hardening (Before Deployment)

- [ ] Update `api_optimized.R` with CORS whitelist
- [ ] Add rate limiting filter to `api_optimized.R`
- [ ] Replace logging filter with sanitized version
- [ ] Add input validation to `/predict` endpoint
- [ ] Create `.gitignore` in project root
- [ ] Create `.dockerignore` in project root
- [ ] Test all security fixes locally

### Phase 2: Docker Containerization

- [ ] Create corrected `Dockerfile` in project root
- [ ] Build image locally: `docker build -t covid-api .`
- [ ] Test container: `docker run -p 8000:8000 covid-api`
- [ ] Verify health endpoint: `curl http://localhost:8000/health`
- [ ] Test prediction endpoint with sample data
- [ ] Verify SHAP values return correctly

### Phase 3: Backend Deployment (Render.com)

- [ ] Push code to GitHub repository
- [ ] Create Render.com account (GitHub login)
- [ ] Create new "Web Service"
- [ ] Select Docker environment
- [ ] Choose Free instance type
- [ ] Set health check path: `/health`
- [ ] Deploy and wait for build (~8-12 minutes)
- [ ] Note deployment URL (e.g., `https://covid-api.onrender.com`)
- [ ] Test health endpoint on production URL

### Phase 4: Frontend Deployment (Cloudflare Pages)

- [ ] Create Cloudflare account
- [ ] Go to Cloudflare Pages
- [ ] Connect GitHub repository
- [ ] Configure build settings:
  - Root directory: `web-app`
  - Build command: `npm run build`
  - Build output: `dist`
- [ ] Set environment variable: `VITE_API_URL=https://your-api.onrender.com`
- [ ] Deploy
- [ ] Note frontend URL (e.g., `https://covid-predictor.pages.dev`)

### Phase 5: Post-Deployment Verification

- [ ] Update CORS whitelist in `api_optimized.R` with actual frontend domain
- [ ] Redeploy backend with updated CORS
- [ ] Test full flow: form submission → API call → results display
- [ ] Verify CORS blocks requests from unauthorized origins
- [ ] Test rate limiting (30 rapid requests should trigger 429)
- [ ] Verify no PHI appears in Render logs
- [ ] Test cold start recovery (wait 20 min, then make request)
- [ ] Document final URLs for paper/presentation

### Phase 6: Scientific Documentation

- [ ] Create `model_card.yaml` with model metadata
- [ ] Document all R package versions
- [ ] Record SHAP configuration (B=5, 16 background samples)
- [ ] Note optimal threshold (0.3184) and its derivation
- [ ] Archive final Docker image hash

---

## Files to Modify/Create

| File | Action | Purpose |
|------|--------|---------|
| `Dockerfile` | CREATE | Production container configuration |
| `.dockerignore` | CREATE | Exclude sensitive/unnecessary files from image |
| `.gitignore` | CREATE | Prevent committing secrets and data |
| `api_optimized.R` | MODIFY | Add security fixes (CORS, rate limit, validation, logging) |
| `model_card.yaml` | CREATE | Scientific reproducibility documentation |
| `web-app/.env.production` | CREATE (optional) | Or use Cloudflare environment variables |

---

## Appendix: Model Card Template

```yaml
# model_card.yaml
model_name: COVID-19 Mortality Risk Calculator
version: 1.0.0
date_created: 2026-02-07
last_updated: 2026-02-07

model_details:
  framework: tidymodels (R)
  algorithm: Random Forest (ranger)
  task: Binary classification (mortality prediction)

training_data:
  source: Peruvian COVID-19 cohort (GastroCOVID study)
  total_samples: 1313
  training_split: 1050 (80%)
  test_split: 263 (20%)
  class_balance: 16% mortality, 84% survival

features:
  count: 8 clinical variables
  list:
    - edad (age): numeric, 18-120 years
    - sexo (sex): categorical, hombre/mujer
    - severidad_sars: categorical, Leve/Moderado/Severo
    - albumina: numeric, serum albumin g/dL
    - plaquetas: numeric, platelet count /uL
    - bilirrtotal: numeric, total bilirubin mg/dL
    - sxingr_disnea: boolean, dyspnea at admission
    - sxingr_cefalea: boolean, headache at admission

preprocessing:
  imputation: KNN (k=5 neighbors) for numeric, mode for categorical
  normalization: included in tidymodels recipe
  class_balancing: SMOTE during training

performance:
  optimal_threshold: 0.3184 (Youden index)
  target_sensitivity: 0.90
  validation: 5-fold cross-validation

explainability:
  method: SHAP (Shapley Additive Explanations)
  implementation: DALEX predict_parts with type="shap"
  background_samples: 16 (stratified, 8 per class)
  permutations: B=5

reproducibility:
  random_seed: 2026
  r_version: 4.3.2
  key_packages:
    ranger: "0.16.0"
    tidymodels: "1.1.1"
    DALEX: "2.4.3"
    plumber: "1.2.1"

deployment:
  api_version: v1
  container: Docker (rocker/r-ver:4.3.2)
  hosting: Render.com (free tier)
  frontend: Cloudflare Pages

ethical_considerations:
  intended_use: Clinical decision support for COVID-19 mortality risk
  limitations:
    - Trained on single-center Peruvian cohort
    - May not generalize to other populations
    - Requires external validation before clinical use
  warnings:
    - Not a substitute for clinical judgment
    - Should be used in conjunction with other clinical assessments
```

---

## Conclusion

Antigravity's plan provides a reasonable architectural foundation but requires significant corrections before deployment:

1. **Platform Change:** Railway → Render.com (mandatory for zero cost)
2. **Security Hardening:** 4 critical vulnerabilities must be fixed
3. **Dockerfile Corrections:** Add missing packages and security features
4. **Scientific Documentation:** Add model card and version tracking

The improved plan achieves true zero-cost deployment while maintaining scientific rigor and security compliance.

---

*Report generated by Claude Code audit on February 7, 2026*
