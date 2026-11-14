# 📊 Scoring de Risque & Priorisation des Contrôles d'Audit (Python • PostgreSQL • Power BI)

**Auteur :** Sitapha KONATE  
**Domaine :** Data Science • Data Engineering • Business Intelligence (Audit & Conformité Financière)  
**Jeu de données :** *Audit Data* — UCI Machine Learning Repository (ID 475, 776 entités)

---

## 🎯 1. Problématique Métier

Les équipes d'audit financier disposent d'une capacité opérationnelle limitée à **10 % du volume total des dossiers**. Une sélection aléatoire ou manuelle entraîne une perte de temps considérable sur des dossiers conformes tout en laissant passer des anomalies financières majeures.

> **Question centrale :** *Parmi les 10 % de dossiers que nous pouvons contrôler, comment identifier le plus grand nombre possible d'entreprises présentant une non-conformité importante ?*

Ce projet implémente un **pipeline décisionnel complet de bout en bout** permettant d'attribuer un score de risque probabiliste à chaque dossier, d'industrialiser le stockage et la segmentation métier sous **PostgreSQL**, et d'offrir aux auditeurs un simulateur interactif sous **Power BI**.

---

## 🏗️ 2. Architecture Technique du Projet

```text
[Données Brutes CSV] 
       │
       ▼ (Python : Scikit-Learn, Pandas, SQLAlchemy)
[Nettoyage Anti-Leakage & Validation Croisée Out-Of-Fold (3 Modèles)]
       │
       ▼ (Ingestion Relationnelle)
[PostgreSQL : Base 'audit_risk_db' • Contraintes • Vues Analytiques (CTE & Window Functions)]
       │
       ▼ (Connexion Directe & Modélisation DAX)
[Power BI : Simulateur What-If (Capacité %) • Segmentation Métier • Consensus Modèles]
```

### Structure du dépôt
```text
risk_priorization/
├── audit_data/
│   ├── audit_risk.csv                 # Snapshot officiel des données brutes
│   └── trial.csv                      # Données intermédiaires de référence
├── notebooks/
│   └── 01_modeling_and_ingestion.ipynb # Préparation, benchmarking OOF et export SQL
├── sql/
│   ├── 01_schema_ddl.sql              # Création des tables, clés étrangères et contraintes
│   └── 02_analytical_views.sql        # Vues Power BI, segmentation et Window Functions
├── powerbi/
│   └── Audit_Risk_Dashboard.pbix      # Tableau de bord décisionnel (3 pages)
├── docs/
│   └── resume_executif_audit.pdf      # Synthèse exécutive et dictionnaire des variables
└── README.md
```

---

## 🔬 3. Méthodologie & Rigueur Scientifique (Python)

### Prévention des fuites de données (*Data Leakage*)
Dans le jeu de données d'origine, la variable cible `Risk` est déterminée mathématiquement par le score global `Audit_Risk`. Toutes les variables calculées *a posteriori* par les auditeurs (`Audit_Risk`, `Inherent_Risk`, `CONTROL_RISK`, `Detection_Risk`, `Score`, `Risk_A` à `Risk_F`) ainsi que les variables colinéaires (`TOTAL`, `Prob`) ont été écartées.

Le modèle s'appuie exclusivement sur **8 variables brutes observables avant contrôle** :
* **Anomalies financières directes :** `PARA_A` (écarts dépenses planifiées), `PARA_B` (écarts dépenses non planifiées), `Money_Value` (montants d'anomalies passées), `numbers` (fréquence des anomalies).
* **Contexte géographique et sectoriel :** `District_Loss` (perte historique du district), `PROB` (probabilité de perte du district), `Sector_score` (risque sectoriel).
* **Historique de l'entité :** `History` (pertes historiques moyennes sur 10 ans).

### Validation Croisée *Out-Of-Fold* (OOF)
Pour évaluer 100 % du portefeuille (776 entités) sans biais de surapprentissage :
1. Découpage stratifié en **5 plis (`StratifiedKFold`)** avec `cross_val_predict`.
2. Traitement des valeurs aberrantes (`Money_Value` via méthode IQR) appliqué **uniquement sur les plis d'entraînement**, conservant les cas extrêmes intacts lors de l'évaluation.
3. Comparaison de 3 algorithmes : **Régression Logistique**, **Random Forest** et **Gradient Boosting**.

---

## 📈 4. Résultats Clés & Impact Opérationnel

Sur un portefeuille de **776 dossiers** comprenant **305 non-conformités avérées** (taux de base de **39,3 %**), le ciblage des **10 % les plus risqués (78 dossiers)** atteint le **plafond théorique de performance** :

| Indicateur de Performance | Contrôle Aléatoire | Modèle Champion (Top 10 %) | Impact Métier |
| :--- | :---: | :---: | :--- |
| **Précision@10%** (Taux de succès) | 39,3 % | **100,0 %** | **78 fraudes détectées sur 78 contrôles** |
| **Rappel@10%** (Couverture totale) | 10,0 % | **25,6 %** | Plafond mathématique atteignable à 10 % |
| **Lift@10%** (Multiplicateur) | 1,00x | **2,54x** | **2,54 fois plus efficace** qu'un audit au hasard |
| **Enjeu Financier Sécurisé** | ~8 338 Crores | **13 649,15 Crores** | **64,3 % de l'enjeu financier total** intercepté |

### Segmentation Métier Déployée dans PostgreSQL (`vw_audit_master`)

| Segment Métier | Dossiers | Fraudes Réelles | Taux de Fraude | Enjeu Financier (Crores) |
| :--- | :---: | :---: | :---: | :---: |
| **1. Urgence Critique (Top 10 % + Fort écart PARA)** | 71 | 71 | **100,0 %** | 12 339,32 |
| **2. Alerte Prioritaire (Top 10 %)** | 7 | 7 | **100,0 %** | 1 309,83 |
| **3. Surveillance Renforcée (Risque Modéré)** | 267 | 210 | **78,7 %** | 6 799,84 |
| **4. Conformité Standard (Faible Risque)** | 431 | 17 | **3,9 %** | 789,82 |

---

## 🗄️ 5. Aperçu Technique (SQL & DAX)

### Exemple de Vue Analytique PostgreSQL (`Window Functions` & Segmentation)
```sql
CREATE OR REPLACE VIEW vw_audit_master AS
WITH predictions_pivot AS (
    SELECT 
        audit_id,
        MAX(CASE WHEN model_name = 'LogisticRegression' THEN proba_risque END) AS proba_logreg,
        MAX(CASE WHEN model_name = 'RandomForest' THEN proba_risque END) AS proba_rf,
        MAX(CASE WHEN model_name = 'GrandientBoosting' THEN proba_risque END) AS proba_gb
    FROM model_predictions
    GROUP BY audit_id
)
SELECT 
    a.audit_id,
    a.location_id,
    (a.para_a + a.para_b + COALESCE(a.money_value, 0)) AS enjeu_financier_total,
    p.proba_logreg,
    ROW_NUMBER() OVER (
        ORDER BY p.proba_logreg DESC, (a.para_a + a.para_b + COALESCE(a.money_value, 0)) DESC
    ) AS rang_priorite
FROM raw_audits a
JOIN predictions_pivot p ON a.audit_id = p.audit_id;
```

### Mesure DAX : Simulateur Dynamique de Capacité d'Audit
```dax
Fraudes Captees (Simule) = 
VAR SeuilRang = ROUNDUP([Total Dossiers] * 'Capacite Controle (%)'[Valeur Capacite Controle (%)], 0)
RETURN
CALCULATE(
    SUM(vw_audit_master[risk_target]),
    FILTER(vw_audit_master, vw_audit_master[rang_priorite] <= SeuilRang)
)
```

---

## 📊 6. Restitution Décisionnelle (Power BI)

Le tableau de bord s'articule autour de **3 vues complémentaires** :
1. **Vue Exécutive & Simulateur de Capacité :** Pilotage en temps réel du Lift, de la Précision et des montants sécurisés via un curseur de capacité d'audit (`5 %` à `50 %`).
2. **Poste de Pilotage des Auditeurs :** Liste d'action opérationnelle filtrable par segment métier et localité, classée par rang de priorité avec barres de données sur l'enjeu financier.
3. **Diagnostic Géographique & Consensus des Modèles :** Cartographie des localités à risque et nuage de points croisant la Régression Logistique et le Random Forest pour valider la robustesse des scores.


![Vue Exécutive Power BI](images/page1.png)
![Poste de Pilotage Auditeurs](images/page2.png)
![Consensus des Modèles](images/page3.png)
