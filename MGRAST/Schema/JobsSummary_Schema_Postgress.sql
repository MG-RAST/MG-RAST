
-- table for all jobs

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

CREATE TABLE data_summary (
  name text NOT NULL,
  abundance integer NOT NULL,
  type text,
  source text,
  jobs integer[]
);
CREATE INDEX data_summary_name ON data_summary (name);
CREATE INDEX data_summary_type ON data_summary (type);
CREATE INDEX data_summary_source ON data_summary (source);

-- array sum function

CREATE FUNCTION sum_array(anyarray)
RETURNS bigint AS $$
SELECT SUM($1[i]) FROM generate_series(array_lower($1,1), array_upper($1,1)) g(i);
$$ LANGUAGE SQL IMMUTABLE;

-- below are tables per job

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
  md5s char(32)[],
  level integer
);
CREATE INDEX j#_lca_#_lca ON j#_lca_# (lca);
CREATE INDEX j#_lca_#_md5s ON j#_lca_# USING gin(md5s);
CREATE INDEX j#_lca_#_level ON j#_lca_# (level);
