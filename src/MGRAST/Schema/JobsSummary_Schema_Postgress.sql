
-- table for all jobs

DROP TABLE IF EXISTS job_tables;
CREATE TABLE job_tables (
  _id SERIAL PRIMARY KEY,
  _ctime timestamp NOT NULL DEFAULT LOCALTIMESTAMP,
  job_id integer NOT NULL,
  table_name text UNIQUE NOT NULL, 
  table_type text NOT NULL, 
  seq_db_name text NOT NULL,
  seq_db_version text NOT NULL,
  pipeline text NOT NULL,
  loaded boolean,
  indexed boolean
);
CREATE INDEX job_tables_id ON job_tables (job_id);
CREATE UNIQUE INDEX job_tables_table_name ON job_tables (table_name);
CREATE TRIGGER job_tables_trigger_index AFTER UPDATE ON job_tables FOR EACH ROW EXECUTE PROCEDURE index_job_table();

-- trigered function to index job tables

CREATE OR REPLACE FUNCTION index_job_table() RETURNS trigger AS $$
DECLARE
  index_num INT := 0;
  this_table TEXT := NEW.table_name;
BEGIN
  SELECT COUNT(ci.relname) INTO index_num FROM pg_index i, pg_class ci, pg_class ct
    WHERE i.indexrelid=ci.oid AND i.indrelid=ct.oid AND i.indisprimary IS FALSE AND ct.relname=this_table;
  IF NEW.loaded IS TRUE AND index_num = 0 THEN
    IF NEW.table_type = 'protein' THEN
      EXECUTE 'CREATE INDEX ' || this_table || '_md5 ON ' || this_table || ' (md5) WITH (FILLFACTOR=100)';
      EXECUTE 'CREATE INDEX ' || this_table || '_exp_avg ON ' || this_table || ' (exp_avg) WITH (FILLFACTOR=100)';
      EXECUTE 'CREATE INDEX ' || this_table || '_seek_length ON ' || this_table || ' (seek,length) WITH (FILLFACTOR=100)';
    ELSIF NEW.table_type = 'ontology' THEN
      EXECUTE 'CREATE INDEX ' || this_table || '_id ON ' || this_table || ' (id) WITH (FILLFACTOR=100)';
      EXECUTE 'CREATE INDEX ' || this_table || '_md5s ON ' || this_table || ' USING gin(md5s)';
      EXECUTE 'CREATE INDEX ' || this_table || '_source ON ' || this_table || ' (source) WITH (FILLFACTOR=100)';
    ELSIF NEW.table_type = 'function' THEN
      EXECUTE 'CREATE INDEX ' || this_table || '_function ON ' || this_table || ' (function) WITH (FILLFACTOR=100)';
      EXECUTE 'CREATE INDEX ' || this_table || '_md5s ON ' || this_table || ' USING gin(md5s)';
      EXECUTE 'CREATE INDEX ' || this_table || '_source ON ' || this_table || ' (source) WITH (FILLFACTOR=100)';
    ELSIF NEW.table_type = 'organism' THEN
      EXECUTE 'CREATE INDEX ' || this_table || '_organism ON ' || this_table || ' (organism) WITH (FILLFACTOR=100)';
      EXECUTE 'CREATE INDEX ' || this_table || '_md5s ON ' || this_table || ' USING gin(md5s)';
      EXECUTE 'CREATE INDEX ' || this_table || '_source ON ' || this_table || ' (source) WITH (FILLFACTOR=100)';
    ELSIF NEW.table_type = 'lca' THEN
      EXECUTE 'CREATE INDEX ' || this_table || '_lca ON ' || this_table || ' (lca) WITH (FILLFACTOR=100)';
      EXECUTE 'CREATE INDEX ' || this_table || '_md5s ON ' || this_table || ' USING gin(md5s)';
      EXECUTE 'CREATE INDEX ' || this_table || '_level ON ' || this_table || ' (level) WITH (FILLFACTOR=100)';
    ELSE
      RETURN NULL;
    END IF;
    RETURN NEW;
  ELSE
    RETURN NULL;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- below are tables per job (templates)

CREATE TABLE j#_protein_# (
  _id integer PRIMARY KEY,
  md5 char(32) NOT NULL,
  abundance integer NOT NULL, 
  eval_min varchar(9),
  eval_max varchar(9),
  exp_avg real,
  exp_stdv real,
  evals integer[5],
  len_min real,
  len_max real,
  len_avg real,
  len_stdv real,
  lens integer[5],
  ident_min real,
  ident_max real,
  ident_avg real,
  ident_stdv real,
  idents integer[5],
  seek integer,
  length integer
);
CREATE INDEX j#_protein_#_md5 ON j#_protein_# (md5);
CREATE INDEX j#_protein_#_exp_avg ON j#_protein_# (exp_avg);
CREATE INDEX j#_protein_#_seek_length ON j#_protein_# (seek,length);


CREATE TABLE j#_function_# (
  _id integer PRIMARY KEY,
  function text NOT NULL,
  abundance integer NOT NULL, 
  eval_min varchar(9),
  eval_max varchar(9),
  exp_avg real,
  exp_stdv real,
  evals integer[5],
  len_min real,
  len_max real,
  len_avg real,
  len_stdv real,
  lens integer[5],
  ident_min real,
  ident_max real,
  ident_avg real,
  ident_stdv real,
  idents integer[5],
  md5s char(32)[],
  source text NOT NULL
);
CREATE INDEX j#_function_#_function ON j#_function_# (function);
CREATE INDEX j#_function_#_md5s ON j#_function_# USING gin(md5s);
CREATE INDEX j#_function_#_source ON j#_function_# (source);


CREATE TABLE j#_organism_# (
  _id integer PRIMARY KEY,
  organism text NOT NULL,
  abundance integer NOT NULL, 
  eval_min varchar(9),
  eval_max varchar(9),
  exp_avg real,
  exp_stdv real,
  evals integer[5],
  len_min real,
  len_max real,
  len_avg real,
  len_stdv real,
  lens integer[5],
  ident_min real,
  ident_max real,
  ident_avg real,
  ident_stdv real,
  idents integer[5],
  md5s char(32)[],
  source text NOT NULL,
  ncbi_tax_id integer
);
CREATE INDEX j#_organism_#_organism ON j#_organism_# (organism);
CREATE INDEX j#_organism_#_md5s ON j#_organism_# USING gin(md5s);
CREATE INDEX j#_organism_#_source ON j#_organism_# (source);


CREATE TABLE j#_ontology_# (
  _id integer PRIMARY KEY,
  id text NOT NULL,
  abundance integer NOT NULL, 
  eval_min varchar(9),
  eval_max varchar(9),
  exp_avg real,
  exp_stdv real,
  evals integer[5],
  len_min real,
  len_max real,
  len_avg real,
  len_stdv real,
  lens integer[5],
  ident_min real,
  ident_max real,
  ident_avg real,
  ident_stdv real,
  idents integer[5],
  md5s char(32)[],
  source text NOT NULL,
  annotation text
);
CREATE INDEX j#_ontology_#_id ON j#_ontology_# (id);
CREATE INDEX j#_ontology_#_md5s ON j#_ontology_# USING gin(md5s);
CREATE INDEX j#_ontology_#_source ON j#_ontology_# (source);


CREATE TABLE j#_lca_# (
  _id integer PRIMARY KEY,
  lca text NOT NULL,
  abundance integer NOT NULL,
  eval_min varchar(9),
  eval_max varchar(9),
  exp_avg real,
  exp_stdv real,
  evals integer[5],
  len_min real,
  len_max real,
  len_avg real,
  len_stdv real,
  lens integer[5],
  ident_min real,
  ident_max real,
  ident_avg real,
  ident_stdv real,
  idents integer[5],
  md5s integer,
  level integer
);
CREATE INDEX j#_lca_#_lca ON j#_lca_# (lca);
CREATE INDEX j#_lca_#_md5s ON j#_lca_# USING gin(md5s);
CREATE INDEX j#_lca_#_level ON j#_lca_# (level);
