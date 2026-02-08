# ==== BIVARIATE ANALYSIS: ASSOCIATION BETWEEN MORTALITY ====

# Libraries:
library(dplyr)
library(tidyverse)
library(gtsummary)
library(flextable)
library(officer)

# Creating the table:
tbl_2 <- df_clean %>%
  select(- id) %>%
  tbl_summary(
    by = fallecido,
    missing = 'no',
    type = list(
      all_of(cols_contin_normal) ~ 'continuous',
      all_of(cols_contin_non_normal) ~ 'continuous'),
    statistic = list(
      all_categorical() ~ '{n} ({p})',
      all_of(cols_contin_normal) ~ '{mean} (+/- {sd})',
      all_of(cols_contin_non_normal) ~ '{median} ({p25} - {p75})'),
    digits = list( 
      all_continuous() ~ 1,
      all_categorical() ~ 1),
    value = list(all_of(cols_logical) ~ TRUE),
    sort = list(all_categorical() ~ 'frequency')
  ) %>%
  add_p()

# Exporting bv_tech_vdot_gustaria:
tbl_2_export <- tbl_2 %>%
  as_flex_table() %>%
  font(font = 'Times New Roman', part = 'all') %>%
  fontsize(size = 10, part = 'all') %>%
  add_footer_lines('Para las variables categóricas, el porcentaje se presenta entre paréntesis; el denominador total varia ligeramente por data faltante.') %>% 
  autofit()

save_as_docx(tbl_2_export, path = 'tbl_2_export.docx')
