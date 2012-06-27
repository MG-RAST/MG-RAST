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
  is_protein boolean
);
COPY md5s (version,job,md5,abundance,evals,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,seek,length,is_protein) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX md5s_key ON md5s (version, job, md5);
CREATE INDEX md5s_job_protein ON md5s (job, is_protein);
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
COPY functions (version,job,function,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX functions_key ON functions (version, job, function, source);
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
COPY organisms (version,job,organism,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source,ncbi_tax_id) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX organisms_key ON organisms (version, job, organism, source);
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
COPY ontologies (version,job,id,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source,annotation) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX ontologies_key ON ontologies (version, job, id, source);
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
COPY lcas (version,job,lca,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,level) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX lcas_key ON lcas (version, job, lca);
CREATE INDEX lcas_level ON lcas (level);
