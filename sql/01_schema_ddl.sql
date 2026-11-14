-- 1. Table des données brutes d'audit
create table raw_audits(
	audit_id SERIAL PRIMARY KEY,
    location_id VARCHAR(20),
    sector_score NUMERIC(10, 4),
    para_a NUMERIC(12, 4),
    para_b NUMERIC(12, 4),
    total NUMERIC(12, 4),
    numbers NUMERIC(10, 4),
    money_value NUMERIC(14, 4),
    district_loss INTEGER,
    prob_district NUMERIC(6, 4),
    history NUMERIC(10, 4),
    prob_history NUMERIC(6, 4),
    risk_target INTEGER CHECK (risk_target IN (0, 1))
);


-- 2. Table des prédictions multi-modèles (reliée par clé étrangère)
create table model_predictions(
	prediction_id serial primary key,
	audit_id integer references raw_audits(audit_id) on delete cascade,
	model_name varchar(30) not null,
	proba_risque numeric(8,6) not null,
	evaluation_type varchar(30) not null, -- ex: 'OOF_CV' (validation croisée sur les 777)
	created_at timestamp default current_timestamp
);


-- Index pour accélérer les jointures futures avec Power BI
create index idx_predictions_audit_id on model_predictions(audit_id);
create index idx_predictions on model_predictions(model_name);


select * from raw_audits;
select * from model_predictions;