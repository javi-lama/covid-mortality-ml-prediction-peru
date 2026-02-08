# ==== DATA DIAGNOSIS AND PLANNING ====

# Libraries:
library(tidyverse)
library(dplyr)
library(janitor)
library(naniar)

# Defining df_raw:
df_raw <- read.csv('database_gastrocovid_raw.csv')

# Clean column names:
df_raw <- clean_names(df_raw)

# Initial de-selecting useless rows:
df_clean <- df_raw %>%
  select(-c(automedicacion_si_anotar_farmacos,
            otros,
            dias_uci,
            dias_hospitalizado_promedio,
            alta_si_1_n0_0,
            ends_with(c('semana_1', 'seman_2', 'sem3', 'alta'), ignore.case = TRUE),
            x, x_1, x_2, x_3, x_4)
  )

# Checking dimensions of dataframe:
dim(df_clean)
# 2313 rows is 1000 rows extra. The extra rows are composed of only NA.

# Eliminating 1000 extra rows
df_clean <- df_clean[1:1313, ]

# Re-checking dimenions:
dim(df_clean)
# Correct number of rows and columns.

# Checking data-type:
glimpse(df_clean)

# Variables to change:
# - hidroxicloroquina -> lgl
# - azitromicina_ceftriaxona -> lgl
# - corticoides -> lgl
# - paracetamol -> lgl
# - ivermectina -> lgl
# - enoxaparina -> lgl
# - ciprofloxacino_levofloxacino -> lgl
# - m_1_f_2 -> chr -> fct
# - talla_m -> dbl
# - dm -> lgl
# - hta -> lgl
# - dislipidemia -> lgl
# - cardiopatia -> lgl 
# - tabaquismo -> lgl 
# - obesidad -> lgl 
# - vhb_vhc -> lgl 
# - erge -> lgl 
# - up -> lgl 
# - cirrosis -> lgl 
# - vih -> lgl 
# - cancer -> lgl 
# - gestacion -> lgl 
# - tbc -> lgl 
# - erc -> lgl 
# - fiebre -> lgl 
# - dolor_de_garganta  -> lgl 
# - odinofagia -> lgl 
# - tos -> lgl 
# - dolor_toracico -> lgl 
# - cefalea -> lgl 
# - fatiga -> lgl 
# - anosmia -> lgl 
# - disnea -> lgl 
# - trastorno_del_sensorio -> lgl 
# - disgeusia -> lgl 
# - nausea_vomito -> lgl 
# - reflujo -> lgl 
# - disfagia -> lgl 
# - dolor_abdominal -> lgl 
# - diarrea -> lgl 
# - ictericia -> lgl 
# - hemorr_dig -> lgl 
# - tgoingreso -> int
# - tgpingreso -> int
# - btingreso -> int
# - aingreso -> int
# - inringreso -> int
# - faingreso -> int
# - ggtingreso -> int
# - pltingreso -> int
# - diaringreso -> lgl 
# - hidroxicloroq -> lgl 
# - cloroquina -> lgl 
# - azitrom -> lgl 
# - ivermectina_1 -> lgl 
# - remdesivir -> lgl 
# - metilprednisolona -> lgl 
# - dexametasona -> lgl 
# - carbapenem -> lgl 
# - fluconazol -> lgl 
# - anfotericina -> lgl 
# - targa -> lgl 
# - anti_tbc -> lgl 
# - heparina_enoxaparina -> lgl 
# - warfarina -> lgl 
# - endoscopia_cpre_colonosc -> lgl 
# - tocilizumab -> lgl 
# - severidad_sars -> fct
# - fallecido_si_1_n0_0  -> lgl 
# - higado_graso -> lgl 

# Columns that need change to lgl:
cols_to_lgl <- c('hidroxicloroquina',
                 'azitromicina_ceftriaxona', 
                 'corticoides',
                 'paracetamol', 
                 'ivermectina',
                 'enoxaparina',
                 'ciprofloxacino_levofloxacino',
                 'dm',
                 'hta',
                 'dislipidemia',
                 'cardiopatia',
                 'tabaquismo',
                 'obesidad',
                 'vhb_vhc',
                 'erge',
                 'up',
                 'cirrosis',
                 'vih',
                 'cancer', 
                 'gestacion',
                 'tbc',
                 'erc',
                 'fiebre',
                 'dolor_de_garganta', 
                 'odinofagia',
                 'tos',
                 'dolor_toracico', 
                 'cefalea',
                 'fatiga', 
                 'anosmia', 
                 'disnea',
                 'trastorno_del_sensorio', 
                 'disgeusia',
                 'nausea_vomito',
                 'reflujo', 
                 'disfagia',
                 'dolor_abdominal', 
                 'diarrea', 
                 'ictericia',
                 'hemorr_dig',
                 'hidroxicloroq',
                 'cloroquina',
                 'azitrom',
                 'ivermectina_1',
                 'remdesivir',
                 'metilprednisolona',
                 'dexametasona',
                 'carbapenem',
                 'fluconazol',
                 'anfotericina',
                 'targa',
                 'anti_tbc',
                 'heparina_enoxaparina',
                 'warfarina',
                 'endoscopia_cpre_colonosc',
                 'tocilizumab',
                 'fallecido_si_1_n0_0',
                 'higado_graso')

df_clean <- df_clean %>%
  mutate(
    across(all_of(cols_to_lgl), ~ as.logical(.))
  )

# Changing m_1_f_2 to factor:
unique(df_clean$m_1_f_2)

df_clean <- df_clean %>%
  mutate(m_1_f_2 = ifelse(m_1_f_2 == 1, 'hombre', 'mujer'))

df_clean <- df_clean %>%
  mutate(m_1_f_2 = as.factor(m_1_f_2))

df_clean <- df_clean %>%
  rename(sexo = m_1_f_2)

class(df_clean$sexo) # As factor

# Changing talla_m to dbl:
unique(df_clean$talla_m)

df_clean %>%
  mutate(
    talla_m = as.numeric(talla_m)
  ) # Introduces NA because a ','

df_clean %>%
  mutate(
    talla_m = gsub(',', '.', talla_m)
  ) %>%
  distinct(talla_m) # Solved

df_clean <- df_clean %>%
  mutate(
    talla_m = gsub(',', '.', talla_m)
  ) %>%
  mutate(talla_m = as.numeric(talla_m))

class(df_clean$talla_m) # As numeric

# Solving outliers
unique(df_clean$talla_m)

df_clean <- df_clean %>%
  mutate(
    talla_m = ifelse(talla_m > 3, talla_m / 100, talla_m)
  )

hist(df_clean$talla_m) # Normally distributed after cleaning!

df_clean %>%
  select(talla_m) %>%
  filter(is.na(talla_m)) # 0 NAs

# Changing tgoingreso as numeric:
unique(df_clean$tgoingreso)

df_clean %>%
  mutate(
    tgoingreso = as.numeric(tgoingreso)
  ) %>%
  select(tgoingreso) %>%
  distinct() # Ready to mutate

df_clean <- df_clean %>%
  mutate(
    tgoingreso = as.numeric(tgoingreso)
  )

# Transforming 0 value (biologically impossible) to NA
df_clean <- df_clean %>%
  mutate(
    tgoingreso = ifelse(tgoingreso == 0, NA_integer_, tgoingreso)
  )

class(df_clean$tgoingreso)

hist(df_clean$tgoingreso) # Right skew

df_clean %>%
  select(tgoingreso) %>%
  filter(is.na(tgoingreso)) # 22 NAs

# Changing tgpingreso as numeric:
unique(df_clean$tgpingreso)

df_clean <- df_clean %>%
  mutate(
    tgpingreso = as.numeric(tgpingreso)
  )

df_clean %>%
  select(tgpingreso) %>%
  distinct()

# Changing 0 value (biologically impossible) to NA
df_clean %>%
  select(tgpingreso) %>%
  filter(tgpingreso < 5) %>%
  distinct()

df_clean <- df_clean %>%
  mutate(
    tgpingreso = ifelse(tgpingreso == 0, NA_integer_, tgpingreso)
  )

class(df_clean$tgpingreso)

hist(df_clean$tgpingreso) # Right skew

df_clean %>%
  select(tgpingreso) %>%
  filter(is.na(tgpingreso)) # 21 NAs

# Changing btingreso as numeric:
unique(df_clean$btingreso) # Lots of ',' separating decimals

df_clean <- df_clean %>%
  mutate(
    btingreso = gsub(',', '.', btingreso)
  )

df_clean <- df_clean %>%
  mutate(
    btingreso = as.numeric(btingreso)
  )

class(df_clean$btingreso)

# Changing 0 value (biologically impossible) to NA
df_clean %>%
  select(btingreso) %>%
  filter(btingreso < 0.5) %>%
  distinct()

df_clean <- df_clean %>%
  mutate(
    btingreso = ifelse(btingreso == 0, NA_integer_, btingreso)
  )

ggplot(df_clean, aes(x = btingreso)) + 
  geom_histogram(binwidth = 0.5) # Right skew

df_clean %>%
  select(btingreso) %>%
  filter(is.na(btingreso)) # 40 NAs

# Changing aingreso as numeric:
unique(df_clean$aingreso) # Are ',' separating decimals

df_clean <- df_clean %>%
  mutate(
    aingreso = gsub(',', '.', aingreso)
  )

df_clean <- df_clean %>%
  mutate(
    aingreso = as.numeric(aingreso)
  )

# Changing 0 value (biologically impossible) to NA
df_clean %>%
  select(aingreso) %>%
  filter(aingreso < 1) %>%
  distinct()

df_clean <- df_clean %>%
  mutate(
    aingreso = ifelse(aingreso == 0, NA_integer_, aingreso)
  )

hist(df_clean$aingreso) # Normally distributed

df_clean %>%
  select(aingreso) %>%
  filter(is.na(aingreso)) # 196 NAs. No NA were created at the moment of as.numeric(). Therefore, all the NAs where introduced at the momento of mutateing aingreos == 0 to NA_integer. Meaning that the source of NA is the lack of lab testing instead of data cleaning!

# Changing inringreso as numeric:
unique(df_clean$inringreso) # Are ',' separating decimals and double values.

df_clean <- df_clean %>% # Solving ',' separating decimals
  mutate(
    inringreso = gsub(',', '.', inringreso)
  )

unique(df_clean$inringreso)

df_clean %>% # Solving double values
  select(inringreso) %>%
  filter(inringreso == "1.03/1.07" | inringreso == "1.01/1.04") # Only 2 rows with a double value each.

df_clean <- df_clean %>%
  mutate(
    inringreso = ifelse(inringreso == "1.03/1.07", '1.03', inringreso),
    inringreso = ifelse(inringreso == "1.01/1.04", '1.01', inringreso)
  )

unique(df_clean$inringreso)

df_clean <- df_clean %>%
  mutate(
    inringreso = as.numeric(inringreso)
  )

df_clean %>%
  select(inringreso) %>%
  distinct()

# Changing 0 value (biologically impossible) to NA
df_clean %>%
  select(inringreso) %>%
  filter(inringreso < 0.5) %>%
  distinct()

df_clean <- df_clean %>%
  mutate(
    inringreso = ifelse(inringreso == 0, NA_integer_, inringreso)
  )

hist(df_clean$inringreso)

# Solving INR = 10 outlier:
df_clean <- df_clean %>%
  mutate(
    inringreso = ifelse(inringreso == 10.00, 1.00, inringreso)
  )

df_clean %>%
  select(inringreso) %>%
  distinct()

hist(df_clean$inringreso) # Right skew.

df_clean %>%
  select(inringreso) %>%
  filter(is.na(inringreso)) # 20 NAs.

# Changing faingreso as numeric:
unique(df_clean$faingreso)

df_clean <- df_clean %>%
  mutate(
    faingreso = as.numeric(faingreso)
  )

df_clean %>%
  select(faingreso) %>%
  distinct()

# Changing 0 value (biologically impossible) to NA
df_clean %>%
  select(faingreso) %>%
  filter(faingreso < 10) %>%
  distinct()

df_clean <- df_clean %>%
  mutate(
    faingreso = ifelse(faingreso == 0, NA_integer_, faingreso)
  )

hist(df_clean$faingreso) # Right skew.

df_clean %>%
  select(faingreso) %>%
  filter(is.na(faingreso)) # 67 NAs.

# Changing ggtingreso as numeric:
unique(df_clean$ggtingreso)

df_clean <- df_clean %>%
  mutate(
    ggtingreso = as.numeric(ggtingreso)
  )

unique(df_clean$ggtingreso)

# Changing 0 value (biologically impossible) to NA
df_clean %>%
  select(ggtingreso) %>%
  filter(ggtingreso < 5) %>%
  distinct()

df_clean <- df_clean %>%
  mutate(
    ggtingreso = ifelse(ggtingreso == 0, NA_integer_, ggtingreso)
  )

hist(df_clean$ggtingreso) # Right skew.

df_clean %>%
  select(ggtingreso) %>%
  filter(is.na(ggtingreso)) # 768 NAs

# Changing pltingreso as numeric:
unique(df_clean$pltingreso) # Values are 6 digits. There are ones separated with ',' and with space

df_clean <- df_clean %>% # Eliminating ','
  mutate(
    pltingreso = gsub(',', '', pltingreso)
  )

unique(df_clean$pltingreso)

df_clean <- df_clean %>% # Eliminating spaces
  mutate(
    pltingreso = gsub(' ', '', pltingreso)
  )

unique(df_clean$pltingreso)

df_clean <- df_clean %>%
  mutate(
    pltingreso = as.numeric(pltingreso)
  ) # No NAs introduced

ggplot(df_clean, aes(x = pltingreso)) +
  geom_histogram(binwidth = 50000)

# Checking outliers:
df_clean %>%
  select(pltingreso) %>%
  filter(pltingreso < 50000 | pltingreso > 550000) # All biologically plausible. No 0 value.

df_clean %>%
  select(pltingreso) %>%
  filter(is.na(pltingreso)) # 0 NAs

# Check that all columns are in the correct data-type:
glimpse(df_clean)

# Needs transformation:
# - n: change name to id + add correct numbers
# - diaringreso: change to lgl
# - severidad_sars: change labels + change to fct

# Changing n column:
df_clean <- df_clean %>%
  mutate(
    n = row_number()
  )

df_clean <- df_clean %>%
  rename(id = n)

# Changing diaringreso column:
unique(df_clean$diaringreso)

df_clean <- df_clean %>%
  mutate(
    diaringreso = as.logical(diaringreso)
  )

# Changing severidad_sars column:
unique(df_clean$severidad_sars)

df_clean <- df_clean %>%
  mutate(
    severidad_sars = case_when(
      severidad_sars %in% c("LEVE", "ASINT", "Leve", "leve") ~ 'Leve',
      severidad_sars %in% c("MODERADO", "MODERADA", "Moderado", "Moderada") ~ 'Moderado',
      severidad_sars %in% c("SEVERO", "Severo", "Severa", "severa") ~ 'Severo',
      TRUE ~ NA_character_
    )
  )

df_clean <- df_clean %>%
  mutate(severidad_sars = factor(severidad_sars,
                                 levels = c('Leve', 'Moderado', 'Severo')))

class(df_clean$severidad_sars)

# Check second-time that all columns are in the correct data-type:
glimpse(df_clean)

# Transforming imc column using the column of OUR CLEAN dataframe:
hist(df_clean$peso) # No outliers, normal distribution.
hist(df_clean$talla_m) # No outliers, normal distribution.

df_clean <- df_clean %>%
  mutate(
    imc = (peso / (talla_m^2))
  )

class(df_clean$imc)

hist(df_clean$imc) # No outliers, normal distribution.

df_clean %>%
  select(imc) %>%
  summary() # All plausible values.

df_clean %>%
  select(imc) %>%
  filter(is.na(imc)) # 0 NAs.

# Mayor renaming of columns of df_clean:
df_clean %>%
  colnames()

df_clean <- df_clean %>%
  rename(automed_hidroxicloroquina = hidroxicloroquina,
         automed_azitro_ceftriax = azitromicina_ceftriaxona,
         automed_corticoides = corticoides,
         automed_paracetamol = paracetamol,
         automed_ivermectina = ivermectina,
         automed_enoxaparina = enoxaparina,
         automed_fluoroquinolonas = ciprofloxacino_levofloxacino,
         ant_dm = dm,
         ant_hta = hta,
         ant_dislipidemia = dislipidemia,
         ant_cardiopatia = cardiopatia,
         ant_tabaquismo = tabaquismo,
         ant_obesidad = obesidad,
         ant_hepatitisviral = vhb_vhc,
         ant_erge = erge,
         ant_ulcerapeptica = up,
         ant_cirrosis = cirrosis,
         ant_vih = vih,
         ant_cancer = cancer,
         gestante = gestacion,
         ant_tuberculosis = tbc,
         ant_erc = erc,
         sxingr_fiebre = fiebre,
         sxingr_dolorgarganta = dolor_de_garganta,
         sxingr_odinofagia = odinofagia,
         sxingr_tos = tos,
         sxingr_dolortoracico = dolor_toracico,
         sxingr_cefalea = cefalea,
         sxingr_fatiga = fatiga,
         sxingr_anosmia = anosmia,
         sxingr_disnea = disnea,
         sxingr_trastornosensorio = trastorno_del_sensorio,
         sxingr_disgeusia = disgeusia,
         sxingr_nauseavomito = nausea_vomito,
         sxingr_reflujo_gastroesof = reflujo,
         sxingr_disfagia = disfagia,
         sxingr_dolorabdominal = dolor_abdominal,
         sxingr_diarrea = diarrea,
         sxingr_ictericia = ictericia,
         sxingr_hda_hdb = hemorr_dig,
         dias_hospitalizado = dias_sala_gral,
         tgo = tgoingreso,
         tgp = tgpingreso,
         bilirrtotal = btingreso,
         albumina = aingreso,
         inr = inringreso,
         fosfalcal = faingreso,
         ggt = ggtingreso,
         med_hidroxicloroquina = hidroxicloroq,
         med_cloroquina = cloroquina,
         med_azitro = azitrom,
         med_ivermectina = ivermectina_1,
         med_remdesivir = remdesivir,
         med_metilpred = metilprednisolona,
         med_carbapenem = dexametasona,
         med_fluconazol = fluconazol,
         med_dexam = dexametasona,
         med_anfob = anfotericina,
         med_targa = targa,
         med_antitb = anti_tbc,
         med_heparina_enoxa = heparina_enoxaparina,
         med_warfarina = warfarina,
         med_tocilizumab = tocilizumab,
         endo_colono_cpre = endoscopia_cpre_colonosc,
         fallecido = fallecido_si_1_n0_0,
         ant_higadograso = higado_graso
         )

# Deleting diaringreso, as sxingr_diarrea already covers the same fact:
df_clean <- df_clean %>%
  select(- diaringreso)

# Check correlation between imc and ant_obesidad column:
df_clean %>%
  select(imc, ant_obesidad) %>%
  head(n = 30) # Patients with FALSE as ant_obesidad have imc > 30, which does not correlate clinically...

# Decision: overwrite and_obesidad with imc values.
df_clean <- df_clean %>%
  mutate(
    ant_obesidad = ifelse(imc > 30, TRUE, FALSE)
  )

class(df_clean$ant_obesidad) # As logical.

# Check NA heatmap:
vis_miss(df_clean) # Only 1.2% of data is NA. Which is 

# Count absolute NA by column
df_clean %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  pivot_longer(
    cols = everything(),
    names_to = "Column_Name",
    values_to = "NA_Count"
  ) %>%
  as_tibble() %>%
  print(n = 74)

# Count % of NA by column
df_clean %>%
  summarise(across(everything(), ~ mean(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_na") %>%
  arrange(desc(pct_na))

# Using the cut-off of > 15% of NA, ggt column needs to be eliminated.
df_clean <- df_clean %>%
  select(- ggt)

# Missing renaming
df_clean <- df_clean %>%
  rename(plaquetas = pltingreso,
         med_carbapenem = carbapenem)

# Final final check of data-type:
glimpse(df_clean)

# There is no TRUE value in column med_anfob. Decision: eliminate column:
df_clean <- df_clean %>%
  select(- med_anfob)

# Data is clean!!!

# ==== SAVE CLEANED DATA FOR PIPELINE REPRODUCIBILITY ====
saveRDS(df_clean, "data_cleaned.rds")
cat("\n✓ Cleaned data saved to: data_cleaned.rds\n")
cat("  Dimensions:", nrow(df_clean), "rows ×", ncol(df_clean), "columns\n")