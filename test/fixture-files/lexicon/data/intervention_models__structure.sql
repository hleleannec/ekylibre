DROP TABLE IF EXISTS intervention_model_items;
DROP TABLE IF EXISTS intervention_models;

        CREATE TABLE intervention_models (
          reference_name character varying PRIMARY KEY NOT NULL,
          name jsonb,
          category_name jsonb,
          number character varying,
          procedure_reference character varying NOT NULL,
          working_flow numeric(19,4),
          working_flow_unit character varying
        );

        CREATE INDEX intervention_models_reference_name ON intervention_models(reference_name);
        CREATE INDEX intervention_models_name ON intervention_models(name);
        CREATE INDEX intervention_models_procedure_reference ON intervention_models(procedure_reference);

        CREATE TABLE intervention_model_items (
          reference_name character varying PRIMARY KEY NOT NULL,
          procedure_item_reference character varying NOT NULL,
          article_reference character varying,
          indicator_name character varying,
          indicator_value numeric(19,4),
          indicator_unit character varying,
          intervention_model_id character varying
        );

        CREATE INDEX intervention_model_items_reference_name ON intervention_model_items(reference_name);
        CREATE INDEX intervention_model_items_procedure_item_reference ON intervention_model_items(procedure_item_reference);
        CREATE INDEX intervention_model_items_article_reference ON intervention_model_items(article_reference);
        CREATE INDEX intervention_model_items_intervention_model_id ON intervention_model_items(intervention_model_id);
