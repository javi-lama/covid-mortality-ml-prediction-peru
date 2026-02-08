# ==== UNIVARIATE ANALYSIS: PARTICIPANT CHARACTERISTICS ====

# Libraries:
library(dplyr)
library(tidyverse)
library(gtsummary)
library(flextable)
library(officer)

# Setting continuous variable distribution:

# edad:
hist(df_clean$edad) # Seems normal distribution:
shapiro.test(df_clean$edad) # p-value = 2.192e-08. But graph seems normal.
qqnorm(df_clean$edad) # Straight line, will take as NORMAL distribution.

# peso:
hist(df_clean$peso) # Seems normal distribution, but right skewed
shapiro.test(df_clean$peso) # p-value < 2.2e-16.
qqnorm(df_clean$peso) # Banana curve, will take as NON-NORMAL distribution.

# talla_m:
hist(df_clean$talla_m) # Seems normal distribution.
shapiro.test(df_clean$talla_m) # p-value = 2.726e-05
qqnorm(df_clean$talla_m) # Straight line, will take as NORMAL distribution.

# imc:
hist(df_clean$imc) # Seems normal distribution, but right skewed.
shapiro.test(df_clean$imc) # p-value < 2.2e-16
qqnorm(df_clean$imc) # Banana curve, will take as NON-NORMAL distribution.

# dias_hospitalizado:
hist(df_clean$dias_hospitalizado) # Right skewed, will take as NON-NORMAL distribution.

# tgo:
hist(df_clean$tgo) # Right skewed, will take as NON-NORMAL distribution.

# tgp:
hist(df_clean$tgp) # Right skewed, will take as NON-NORMAL distribution.

# bilirrtotal:
hist(df_clean$bilirrtotal) # Right skewed, will take as NON-NORMAL distribution.

# albumina:
hist(df_clean$albumina) # Normally distributed, will take as NORMAL distribution.
shapiro.test(df_clean$albumina) # p-value = 4.221e-09
qqnorm(df_clean$albumina) # Almost straight line, will take as NORMAL distribution.

# inr:
hist(df_clean$inr) # Right skewed, will take as NON-NORMAL distribution.

# fosfalcal:
hist(df_clean$fosfalcal) # Right skewed, will take as NON-NORMAL distribution.

# plaquetas:
hist(df_clean$plaquetas) # Right skewed.
shapiro.test(df_clean$plaquetas) # p-value < 2.2e-16
qqnorm(df_clean$plaquetas) # Banana curve, will take as NON-NORMAL distribution.

# Creating variables for continuous columns to determine its distribution:
cols_contin_normal <- c('edad', 'talla_m', 'albumina')
cols_contin_non_normal <- c('peso', 'imc', 'dias_hospitalizado', 'tgo', 'tgp', 'bilirrtotal', 'inr', 'fosfalcal', 'plaquetas')

# Creating variables for logical columns:
cols_logical <- c('automed_hidroxicloroquina',
                  'automed_azitro_ceftriax',
                  'automed_corticoides',
                  'automed_paracetamol',
                  'automed_ivermectina',
                  'automed_enoxaparina',
                  'automed_fluoroquinolonas',
                  'ant_dm',
                  'ant_hta',
                  'ant_dislipidemia',
                  'ant_cardiopatia',
                  'ant_tabaquismo',
                  'ant_obesidad',
                  'ant_hepatitisviral',
                  'ant_erge',
                  'ant_ulcerapeptica',
                  'ant_cirrosis',
                  'ant_vih',
                  'ant_cancer',
                  'gestante',
                  'ant_tuberculosis',
                  'ant_erc',
                  'sxingr_fiebre',
                  'sxingr_dolorgarganta',
                  'sxingr_odinofagia',
                  'sxingr_tos',
                  'sxingr_dolortoracico',
                  'sxingr_cefalea',
                  'sxingr_fatiga',
                  'sxingr_anosmia',
                  'sxingr_disnea',
                  'sxingr_trastornosensorio',
                  'sxingr_disgeusia',
                  'sxingr_nauseavomito',
                  'sxingr_reflujo_gastroesof',
                  'sxingr_disfagia',
                  'sxingr_dolorabdominal',
                  'sxingr_diarrea',
                  'sxingr_ictericia',
                  'sxingr_hda_hdb',
                  'med_hidroxicloroquina',
                  'med_cloroquina',
                  'med_azitro',
                  'med_ivermectina',
                  'med_remdesivir',
                  'med_metilpred',
                  'med_carbapenem',
                  'med_fluconazol',
                  'med_dexam',
                  'med_targa',
                  'med_antitb',
                  'med_heparina_enoxa',
                  'med_warfarina',
                  'med_tocilizumab',
                  'endo_colono_cpre',
                  'ant_higadograso')

# Table style:
theme_gtsummary_journal(journal = 'nejm')

# Table creation:
tbl_1 <- df_clean %>%
  select(- id) %>%
  tbl_summary(missing = 'ifany', 
              missing_text = 'NA',
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
              sort = list(all_categorical() ~ 'frequency'),
              value = list(all_of(cols_logical) ~ TRUE)
  ) %>% 
  modify_header(label = '**Caracteristicas**') %>% # Modify header
  modify_header(stat_0 = '**Frecuencia**') %>%  
  modify_footnote(all_stat_cols() ~ 'Mediana [Q1, Q3]; n(%); Media (+/- SD)') # Modify footnote

# Export table:
tbl_1_export <- tbl_1 %>%
  as_flex_table() %>%
  font(font = 'Times New Roman', part = 'all') %>%
  fontsize(size = 10, part = 'all') %>% 
  bg(part = 'header', bg = '#EFEFEF') %>% 
  add_footer_lines('Para las variables categoricas, el porcentaje se presenta entre parentesis') %>%
  autofit()

save_as_docx(tbl_1_export, path = 'tbl_1_export.docx') 
