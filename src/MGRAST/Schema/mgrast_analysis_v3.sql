-- index notes:
-- for md5 table
-- 1. param / cutoff lookup: version, job, exp_avg, len_avg, ident_avg
-- for annotation tables
-- 1. param / cutoff lookup: version, job, exp_avg, len_avg, ident_avg, source
-- 2. annotation searching: version, name, source

CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_on = now(); 
   RETURN NEW;
END;
$$ language 'plpgsql';

DROP TABLE IF EXISTS job_info;
CREATE TABLE job_info (
 updated_on timestamp NOT NULL DEFAULT LOCALTIMESTAMP,
 version smallint NOT NULL,
 job integer NOT NULL,
 loaded boolean
);
CREATE UNIQUE INDEX job_info_vj ON job_info (version, job);
CREATE INDEX job_info_loaded ON job_info (loaded);
CREATE TRIGGER job_info_update_timestamp BEFORE UPDATE ON job_info FOR EACH ROW EXECUTE PROCEDURE update_timestamp();

DROP TABLE IF EXISTS job_md5s;
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
-- COPY job_md5s (version,job,md5,abundance,evals,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,seek,length,is_protein) FROM 'FILE' WITH NULL AS '';
CREATE INDEX job_md5s_vj ON job_md5s (version, job);
CREATE INDEX job_md5s_md5 ON job_md5s (md5);
CREATE INDEX job_md5s_job_lookup ON job_md5s (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS job_functions;
CREATE TABLE job_functions (
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
-- COPY job_functions (version,job,id,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE INDEX job_functions_vj ON job_functions (version, job);
CREATE INDEX job_functions_id ON job_functions (id);
CREATE INDEX job_functions_source ON job_functions (source);
CREATE INDEX job_functions_lookup ON job_functions (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS job_organisms;
CREATE TABLE job_organisms (
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
-- COPY job_organisms (version,job,id,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE INDEX job_organisms_vj ON job_organisms (version, job);
CREATE INDEX job_organisms_id ON job_organisms (id);
CREATE INDEX job_organisms_source ON job_organisms (source);
CREATE INDEX job_organisms_lookup ON job_organisms (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS job_rep_organisms;
CREATE TABLE job_rep_organisms (
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
CREATE INDEX job_rep_organisms_vj ON job_rep_organisms (version, job);
CREATE INDEX job_rep_organisms_id ON job_rep_organisms (id);
CREATE INDEX job_rep_organisms_source ON job_rep_organisms (source);
CREATE INDEX job_rep_organisms_lookup ON job_rep_organisms (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS job_ontologies;
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
-- COPY job_ontologies (version,job,id,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,source) FROM 'FILE' WITH NULL AS '';
CREATE INDEX job_ontologies_vj ON job_ontologies (version, job);
CREATE INDEX job_ontologies_id ON job_ontologies (id);
CREATE INDEX job_ontologies_source ON job_ontologies (source);
CREATE INDEX job_ontologies_lookup ON job_ontologies (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS job_lcas;
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
-- COPY job_lcas (version,job,lca,abundance,exp_avg,exp_stdv,len_avg,len_stdv,ident_avg,ident_stdv,md5s,level) FROM 'FILE' WITH NULL AS '';
CREATE INDEX job_lcas_vj ON job_lcas (version, job);
CREATE INDEX job_lcas_lookup ON job_lcas (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS functions;
CREATE TABLE functions (
 _id integer PRIMARY KEY,
 name text NOT NULL
);
CREATE INDEX functions_name ON functions (name);

DROP TABLE IF EXISTS organisms_ncbi;
CREATE TABLE organisms_ncbi (
 _id integer PRIMARY KEY,
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

DROP TABLE IF EXISTS md5_organism_unique;
CREATE TABLE md5_organism_unique (
md5 char(32) NOT NULL,
organism integer NOT NULL,
source text
);
CREATE INDEX md5_organism_unique_key ON md5_organism_unique (md5, source);

DROP TABLE IF EXISTS ontologies;
CREATE TABLE ontologies (
 _id integer PRIMARY KEY,
 level1 text,
 level2 text,
 level3 text,
 level4 text,
 name text,
 type text
);
CREATE INDEX ontologies_name ON ontologies (name);
CREATE INDEX ontologies_type ON ontologies (type);
