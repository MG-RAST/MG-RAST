## index notes:
# for md5 table
# 1. param / cutoff lookup: version, job, exp_avg, len_avg, ident_avg
# for annotation tables
# 1. param / cutoff lookup: version, job, exp_avg, len_avg, ident_avg, source
# 2. annotation searching: version, name, source

CREATE TABLE job_info (
 version smallint NOT NULL,
 job integer NOT NULL,
 rna_only boolean,
 loaded boolean
);
CREATE UNIQUE INDEX job_info_loaded ON job_info (loaded);
CREATE UNIQUE INDEX job_info_rna ON job_info (rna_only);

CREATE TABLE job_md5s (
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
#COPY job_md5s (version,job,md5,abundance,evals,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,seek,length,is_protein) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX job_md5s_key ON job_md5s (version, job, md5);
CREATE INDEX job_md5s_job_protein ON job_md5s (job, is_protein);
CREATE INDEX job_md5s_seek_length ON job_md5s (seek, length);

CREATE TABLE job_functions (
 version smallint NOT NULL,
 job integer NOT NULL,
 function integer NOT NULL,
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
#COPY job_functions (version,job,function,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX job_functions_key ON job_functions (version, job, function, source);

CREATE TABLE job_organisms (
 version smallint NOT NULL,
 job integer NOT NULL,
 organism integer NOT NULL,
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
#COPY job_organisms (version,job,organism,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX job_organisms_key ON job_organisms (version, job, organism, source);

CREATE TABLE job_rep_organisms (
 version smallint NOT NULL,
 job integer NOT NULL,
 organism integer NOT NULL,
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
CREATE UNIQUE INDEX job_rep_organisms_key ON job_rep_organisms (version, job, organism, source);

CREATE TABLE job_ontologies (
 version smallint NOT NULL,
 job integer NOT NULL,
 id integer NOT NULL,
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
#COPY job_ontologies (version,job,id,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX job_ontologies_key ON job_ontologies (version, job, id, source);

CREATE TABLE job_lcas (
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
#COPY job_lcas (version,job,lca,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,level) FROM 'FILE' WITH NULL AS '';
CREATE UNIQUE INDEX job_lcas_key ON job_lcas (version, job, lca);
CREATE INDEX job_lcas_level ON job_lcas (level);

CREATE TABLE functions (
 _id SERIAL PRIMARY KEY,
 name text NOT NULL
);
CREATE INDEX functions_name ON functions (name);

CREATE TABLE organisms_ncbi (
 _id SERIAL PRIMARY KEY,
 name text NOT NULL,
 tax_domain text,
 tax_kingdom text,
 tax_phylum text,
 tax_class text,
 tax_order text,
 tax_family text,
 tax_genus text,
 tax_species text,
 taxonomy text,
 ncbi_tax_id integer
);
CREATE INDEX organisms_ncbi_name ON organisms_ncbi (name);
CREATE INDEX organisms_ncbi_tax_id ON organisms_ncbi (ncbi_tax_id);

CREATE TABLE ontologies (
 _id SERIAL PRIMARY KEY,
 level1 text,
 level2 text,
 level3 text,
 level4 text,
 id text,
 type text
);
CREATE INDEX ontologies_id ON ontologies (id);
CREATE INDEX ontologies_type ON ontologies (type);
