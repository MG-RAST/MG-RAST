-- index notes:
-- for md5 table
-- 1. param / cutoff lookup: version, job, exp_avg, len_avg, ident_avg
-- for annotation tables
-- 1. param / cutoff lookup: version, job, exp_avg, len_avg, ident_avg, source
-- 2. annotation searching: version, name, source

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

DROP TABLE IF EXISTS sources;
CREATE TABLE sources (
_id integer PRIMARY KEY,
name text NOT NULL,
type text NOT NULL,
description text,
link text );

CREATE INDEX sources_name ON sources (name);
CREATE INDEX sources_type ON sources (type);

DROP TABLE IF EXISTS ontologies;
CREATE TABLE ontologies (
 _id integer PRIMARY KEY,
 level1 text,
 level2 text,
 level3 text,
 level4 text,
 name text,
 source integer REFERENCES sources(_id)
);

CREATE INDEX ontologies_name ON ontologies (name);
CREATE INDEX ontologies_source ON ontologies (source);

DROP TABLE IF EXISTS md5s;
CREATE TABLE md5s (
_id integer PRIMARY KEY,
md5 char(32) NOT NULL,
is_protein boolean
);
CREATE UNIQUE INDEX md5s_md5 ON md5s (md5);
CREATE INDEX md5s_protein ON md5s (is_protein);

DROP TABLE IF EXISTS functions;
CREATE TABLE functions (
 _id integer PRIMARY KEY,
 name text NOT NULL
);
CREATE INDEX functions_name ON functions (name);


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
 md5 integer REFERENCES md5s(_id),
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
CREATE INDEX job_md5s_lookup ON job_md5s (exp_avg, len_avg, ident_avg);
CREATE INDEX job_md5s_index ON job_md5s (seek, length) WHERE seek IS NOT NULL AND length IS NOT NULL; 

DROP TABLE IF EXISTS job_functions;
CREATE TABLE job_functions (
 version smallint NOT NULL,
 job integer NOT NULL,
 id integer REFERENCES functions(_id),
 abundance integer NOT NULL,
 exp_avg real,
 exp_stdv real,
 len_avg real,
 len_stdv real,
 ident_avg real,
 ident_stdv real,
 md5s integer[],
 source integer REFERENCES sources(_id)
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
 id integer REFERENCES organisms_ncbi(_id),
 abundance integer NOT NULL,
 exp_avg real,
 exp_stdv real,
 len_avg real,
 len_stdv real,
 ident_avg real,
 ident_stdv real,
 md5s integer[],
 source integer REFERENCES sources(_id)
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
 id integer REFERENCES organisms_ncbi(_id),
 abundance integer NOT NULL,
 exp_avg real,
 exp_stdv real,
 len_avg real,
 len_stdv real,
 ident_avg real,
 ident_stdv real,
 md5s integer[],
 source integer REFERENCES sources(_id)
);
CREATE INDEX job_rep_organisms_vj ON job_rep_organisms (version, job);
CREATE INDEX job_rep_organisms_id ON job_rep_organisms (id);
CREATE INDEX job_rep_organisms_source ON job_rep_organisms (source);
CREATE INDEX job_rep_organisms_lookup ON job_rep_organisms (exp_avg, len_avg, ident_avg);

DROP TABLE IF EXISTS job_ontologies;
CREATE TABLE job_ontologies (
 version smallint NOT NULL,
 job integer NOT NULL,
 id integer REFERENCES ontologies(_id),
 abundance integer NOT NULL,
 exp_avg real,
 exp_stdv real,
 len_avg real,
 len_stdv real,
 ident_avg real,
 ident_stdv real,
 md5s integer[],
 source integer REFERENCES sources(_id)
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

DROP TABLE IF EXISTS md5_organism_unique;
CREATE TABLE md5_organism_unique (
md5 integer REFERENCES md5s(_id),
organism integer REFERENCES organisms_ncbi(_id),
source integer REFERENCES sources(_id)
);
CREATE INDEX md5_organism_unique_md5 ON md5_organism_unique (md5);
CREATE INDEX md5_organism_unique_organism ON md5_organism_unique (organism);
CREATE INDEX md5_organism_unique_source ON md5_organism_unique (source);

DROP TABLE IF EXISTS md5_annotation;
CREATE TABLE md5_annotation (
md5 integer REFERENCES md5s(_id),
id text NOT NULL,
function integer REFERENCES functions(_id),
organism integer REFERENCES organisms_ncbi(_id),
source integer REFERENCES sources(_id),
is_protein boolean
);
CREATE INDEX md5_annotation_md5 ON md5_annotation (md5);
CREATE INDEX md5_annotation_function ON md5_annotation (function);
CREATE INDEX md5_annotation_organism ON md5_annotation (organism);
CREATE INDEX md5_annotation_source ON md5_annotation (source);


