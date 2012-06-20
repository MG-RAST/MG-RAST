CREATE TABLE md5s (
  version smallint NOT NULL,
  job integer NOT NULL,
  md5 char(32) NOT NULL,
  abundance integer NOT NULL,
  evals integer[5],
  exp_avg real,
  exp_stdv real,
  len_avg real,
  len_stdv real,
  ident_avg real,
  ident_stdv real,
  seek bigint,
  length integer,
  protein boolean
);
CREATE INDEX md5s_key ON md5s (version, job, md5);
CREATE INDEX md5s_job_protein ON md5s (job, protein);
CREATE INDEX md5s_seek_length ON md5s (seek, length);

CREATE TABLE functions (
  version smallint NOT NULL,
  job integer NOT NULL,
  function text NOT NULL,
  abundance integer NOT NULL, 
  exp_avg real,
  exp_stdv real,
  len_avg real,
  len_stdv real,
  ident_avg real,
  ident_stdv real,
  md5s char(32)[],
  source text NOT NULL
);
CREATE INDEX functions_key ON functions (version, job, function, source);
CREATE INDEX functions_md5s ON functions USING gin(md5s);

CREATE TABLE organisms (
  version smallint NOT NULL,
  job integer NOT NULL,
  organism text NOT NULL,
  abundance integer NOT NULL,
  exp_avg real,
  exp_stdv real,
  len_avg real,
  len_stdv real,
  ident_avg real,
  ident_stdv real,
  md5s char(32)[],
  source text NOT NULL,
  ncbi_tax_id integer
);
CREATE INDEX organisms_key ON organisms (version, job, organism, source);
CREATE INDEX organisms_md5s ON organisms USING gin(md5s);

CREATE TABLE ontologies (
  version smallint NOT NULL,
  job integer NOT NULL,
  id text NOT NULL,
  abundance integer NOT NULL,
  exp_avg real,
  exp_stdv real,
  len_avg real,
  len_stdv real,
  ident_avg real,
  ident_stdv real,
  md5s char(32)[],
  source text NOT NULL,
  annotation text
);
CREATE INDEX ontologies_key ON ontologies (version, job, id, source);
CREATE INDEX ontologies_md5s ON ontologies USING gin(md5s);

CREATE TABLE lcas (
  version smallint NOT NULL,
  job integer NOT NULL,
  lca text NOT NULL,
  abundance integer NOT NULL,
  exp_avg real,
  exp_stdv real,
  len_avg real,
  len_stdv real,
  ident_avg real,
  ident_stdv real,
  md5s integer,
  level integer
);
CREATE INDEX lcas_key ON lcas (version, job, lca);
CREATE INDEX lcas_level ON lcas (level);
