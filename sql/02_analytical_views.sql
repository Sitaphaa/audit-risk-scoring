-- requêtes cte (common table expression) : permet de créer une table temporaire
-- en mémoire. Ici, on en créé 2 (classement_deciles et stats_globales) et
-- on fait leur jointure après (cross join) pour séectionner des observations.

with classement_deciles as (
	select p.model_name, a.audit_id, a.risk_target, p.proba_risque,
	-- Découpe chaque modèle en 10 tranches de risque (1 = Top 10% le plus risqué)
	ntile(10) over (partition by p.model_name order by p.proba_risque desc)
	as decile_risque
	from model_predictions p
	join raw_audits a on p.audit_id=a.audit_id
),

stats_globales as (
	-- Calcul du taux de fraude de référence sur l'ensemble du portefeuille
	select count(*) as total_dossiers, sum(risk_target) as total_fraudes,
	round(avg(risk_target)*100,2) as taux_fraude_base_pct
	from raw_audits
)

select c.model_name as modele, count(*) as dossiers_controles_top10,
	sum(c.risk_target) as fraudes_detectees,
	-- Précision@10% : % de dossiers contrôlés qui sont réellement frauduleux
	round(avg(c.risk_target) * 100, 2) as precision_at_10_pct,
    
	-- Rappel@10% : % des fraudes totales du portefeuille attrapées
    round(sum(c.risk_target)::numeric / g.total_fraudes * 100, 2) as rappel_at_10_pct,
    
	-- Lift@10% : Multiplicateur d'efficacité par rapport au hasard
    round((avg(c.risk_target) * 100) / g.taux_fraude_base_pct, 2) as lift_at_10

from classement_deciles c
cross join stats_globales g
where c.decile_risque = 1
group by c.model_name, g.total_fraudes, g.taux_fraude_base_pct
order by precision_at_10_pct desc, rappel_at_10_pct desc;


select model_name, count(*) from model_predictions group by model_name;

-- 1. Supprimer les lignes en double de LogisticRegression 
-- (on garde le plus petit prediction_id pour chaque audit_id)
delete from model_predictions
where prediction_id not in (
    select min(prediction_id)
    from model_predictions
    group by audit_id, model_name
);

-- 2. Ajouter une contrainte d'unicité pour interdire tout doublon futur à l'insertion
alter table model_predictions
add constraint uq_audit_model unique (audit_id, model_name);

-- 3. Vérifier que chaque modèle a bien exactement 776 lignes
select model_name, count(*) as nb_lignes
from model_predictions
group by model_name
order by model_name;


-- VUE 1 : VUE MAÎTRE POUR POWER BI (776 dossiers enrichis et segmentés)
create or replace view vw_audit_master as
	with predictions_pivot as (
		 -- Pivoter les 3 modèles en colonnes pour chaque dossier
		select audit_id,
		max(case when model_name='LogisticRegression' then proba_risque end) as proba_logreg,
		max(case when model_name='RandomForest' then proba_risque end) as proba_rf,
		max(case when model_name='GrandientBoosting' then proba_risque end) as proba_gb
		from model_predictions
		group by audit_id
	),

	classement_strict as(
		select a.audit_id, a.location_id, a.sector_score, a.para_a, a.para_b,
        (a.para_a + a.para_b) as ecart_para_total,
        coalesce(a.money_value, 0) as money_value_clean,
        (a.para_a + a.para_b + coalesce(a.money_value, 0)) as enjeu_financier_total,
        a.numbers as score_anomalies_passees,
        a.district_loss, a.prob_district, a.history, a.risk_target, 
		p.proba_logreg, p.proba_rf, p.proba_gb,
        -- Score de consensus (moyenne des 3 modèles)
        ROUND(((p.proba_logreg + p.proba_rf + p.proba_gb) / 3.0)::NUMERIC, 4) as proba_consensus,
        -- Rang strict de 1 à 776 (départage par enjeu financier si ex-aequo sur la probabilité)
        row_number() over (
            order by p.proba_logreg des, (a.para_a + a.para_b + coalesce(a.money_value, 0)) desc
        ) as rang_priorite,
        -- Percentile de risque (de 0.00 à 1.00) pour filtrage dynamique dans Power BI
        ROUND(percent_rank() over (
            order by p.proba_logreg desc, (a.para_a + a.para_b + coalesce(a.money_value, 0)) desc
        )::NUMERIC, 4) as percentile_rang
    from raw_audits a
    join predictions_pivot p on a.audit_id = p.audit_id
	)
	
	select *,
    -- Indicateur binaire Top 10 % (78 dossiers sur 776)
    case when rang_priorite <= ceil then(0.10 * 776) then 1 else 0 end as est_top_10_pct,
    -- Segmentation métier exploitable par les équipes d'audit
    case 
        when rang_priorite <= ceil(0.10 * 776) and ecart_para_total >= 5.0 
            then '1. Urgence Critique (Top 10% + Fort écart PARA)'
        when rang_priorite <= ceil(0.10 * 776) 
            then '2. Alerte Prioritaire (Top 10%)'
        when proba_logreg >= 0.20 
            then '3. Surveillance Renforcée (Risque Modéré)'
        else '4. Conformité Standard (Faible Risque)'
    end as segment_metier
from classement_strict;


-- VUE 2 : SYNTHÈSE GÉOGRAPHIQUE PAR LOCALITÉ (EDA Orientée Métier)
create or replace view vw_audit_kpis_zone as
select 
    location_id,
    count(*) as total_entreprises,
    sum(risk_target) as total_non_conformites,
    round(AVG(risk_target) * 100, 1) as taux_fraude_reel_pct,
    sum(est_top_10_pct) as dossiers_dans_top10,
    round(sum(enjeu_financier_total)::numeric, 2) as exposition_financiere_totale,
    round(avg(proba_logreg) * 100, 1) as score_risque_moyen_pct
from vw_audit_master
group by location_id
order by dossiers_dans_top10 desc, taux_fraude_reel_pct desc;


-- Questionner les vues
select 
    segment_metier,
    count(*) as nb_dossiers,
    sum(risk_target) as nb_fraudes_reelles,
    ROUND(avg(risk_target) * 100, 1) as taux_fraude_pct,
    ROUND(sum(enjeu_financier_total)::numeric, 2) as montant_total_en_jeu
from vw_audit_master
group by segment_metier
order by segment_metier;