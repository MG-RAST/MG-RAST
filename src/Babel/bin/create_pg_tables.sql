DROP TABLE IF EXISTS md5s;
CREATE TABLE md5s (
_id SERIAL PRIMARY KEY,
md5 char(32) NOT NULL,
is_protein boolean
);

DROP TABLE IF EXISTS functions;
CREATE TABLE functions (
_id SERIAL PRIMARY KEY,
name text NOT NULL
);

DROP TABLE IF EXISTS organisms_ncbi;
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

DROP TABLE IF EXISTS sources;
CREATE TABLE sources (
_id SERIAL PRIMARY KEY,
name text NOT NULL,
source text,
description text,
type text,
url text,
email text,
link text,
title text,
version text,
download_path text[],
download_file text[],
download_date date NOT NULL DEFAULT CURRENT_DATE,
protein_ids integer,
ontology_ids integer,
rna_ids integer,
md5s integer,
uniq_md5s integer,
organisms integer,
ncbi_organisms integer,
contigs integer,
functions integer
);

DROP TABLE IF EXISTS md5_protein;
CREATE TABLE md5_protein (
_id SERIAL PRIMARY KEY,
md5 char(32) NOT NULL,
id text NOT NULL,
function integer REFERENCES functions(_id),
organism integer REFERENCES organisms_ncbi(_id),
source integer REFERENCES sources(_id)
);

DROP TABLE IF EXISTS md5_ontology;
CREATE TABLE md5_ontology (
_id SERIAL PRIMARY KEY,
md5 char(32) NOT NULL,
id text NOT NULL,
function integer REFERENCES functions(_id),
source integer REFERENCES sources(_id)
);

DROP TABLE IF EXISTS md5_rna;
CREATE TABLE md5_rna (
_id SERIAL PRIMARY KEY,
md5 char(32) NOT NULL,
id text NOT NULL,
function integer REFERENCES functions(_id),
organism integer REFERENCES organisms_ncbi(_id),
source integer REFERENCES sources(_id),
tax_rank integer
);

DROP TABLE IF EXISTS md5_lca;
CREATE TABLE md5_lca (
md5 char(32) NOT NULL,
tax_domain text,
tax_phylum text,
tax_class text,
tax_order text,
tax_family text,
tax_genus text,
tax_species text,
tax_strain text,
level integer
);

DROP TABLE IF EXISTS md5_organism_unique;
CREATE TABLE md5_organism_unique (
md5 integer REFERENCES md5s(_id),
organism integer REFERENCES organisms_ncbi(_id),
source integer REFERENCES sources(_id)
);

DROP TABLE IF EXISTS aliases_protein;
CREATE TABLE aliases_protein (
_id SERIAL PRIMARY KEY,
id text NOT NULL,
alias_id text,
alias_source text
);

DROP TABLE IF EXISTS contigs;
CREATE TABLE contigs (
_id SERIAL PRIMARY KEY,
name text NOT NULL,
description text,
length integer,
organism integer REFERENCES organisms_ncbi(_id)
);

DROP TABLE IF EXISTS id2contig;
CREATE TABLE id2contig (
_id SERIAL PRIMARY KEY,
id text NOT NULL,
contig integer REFERENCES contigs(_id),
strand integer,
low integer,
high integer
);

DROP TABLE IF EXISTS ontology_seed;
CREATE TABLE ontology_seed (
_id SERIAL PRIMARY KEY,
level1 text,
level2 text,
level3 text,
level4 text,
id text
);

DROP TABLE IF EXISTS ontology_kegg;
CREATE TABLE ontology_kegg (
_id SERIAL PRIMARY KEY,
level1 text,
level2 text,
level3 text,
level4 text,
id text
);

DROP TABLE IF EXISTS ontology_eggnog;
CREATE TABLE ontology_eggnog (
_id SERIAL PRIMARY KEY,
level1 text,
level2 text,
level3 text,
id text,
type text
);

DROP TABLE IF EXISTS ontologies;
CREATE TABLE ontologies (
 _id SERIAL PRIMARY KEY,
 level1 text,
 level2 text,
 level3 text,
 level4 text,
 id text,
 source integer REFERENCES sources(_id)
);

DROP TABLE IF EXISTS counts;
CREATE TABLE counts (
type text PRIMARY KEY,
count integer
);
