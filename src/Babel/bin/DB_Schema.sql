
DROP TABLE IF EXISTS ACH_DATA;

CREATE TABLE ACH_DATA (
_id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL, 
_ctime timestamp(14) NOT NULL,
md5 varchar(32) NOT NULL,
ID varchar(32),
function integer,
source integer,
organism integer,
organism_group integer,
KEY (md5),
PRIMARY KEY (_id) 
);
CREATE INDEX DATA_ID ON ACH_DATA (ID) USING BTREE;
CREATE INDEX DATA_organism ON ACH_DATA (organism) USING BTREE;
CREATE INDEX DATA_organismGroup ON ACH_DATA (organism_group) USING BTREE; 
CREATE INDEX DATA_md5 ON ACH_DATA (md5) USING BTREE;
CREATE INDEX DATA_md5_source ON ACH_DATA (source,md5) USING BTREE;
CREATE INDEX DATA_function ON ACH_DATA (function) USING BTREE;


DROP TABLE IF EXISTS ACH_FUNCTIONS;

CREATE TABLE ACH_FUNCTIONS (
_id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
function text,
KEY (function(300)),
PRIMARY KEY (_id)
);
CREATE INDEX FUNCTIONS_function ON ACH_FUNCTIONS (function) USING BTREE;


DROP TABLE IF EXISTS ACH_SOURCES;

CREATE TABLE ACH_SOURCES (
_id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
name text,
source text,
IDs integer,
md5s integer,
functions integer,
organisms integer,
email text,
type text,
url text,
link text,
KEY (name(100)),
PRIMARY KEY (_id)
);
CREATE INDEX SOURCES_name ON ACH_SOURCES (name) USING BTREE;


DROP TABLE IF EXISTS ACH_ORGANISMS;

CREATE TABLE ACH_ORGANISMS (
_id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL, 
_ctime timestamp(14) NOT NULL,
name text  NOT NULL,
domain text,
level2 text,
level3 text,
taxonomy text,
ncbi_tax_id integer,
organism_group integer,
KEY (name(100)),
PRIMARY KEY (_id) 
);
CREATE INDEX ORGANISMS_name ON ACH_ORGANISMS (name) USING BTREE;


DROP TABLE IF EXISTS ACH_ID2CONTIG;

CREATE TABLE ACH_ID2CONTIG (
_id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
ID varchar(32),
contigID varchar(32),
contigLength integer,
strand integer,
low integer,
high integer,
md5 varchar(32),
KEY (ID),
PRIMARY KEY (_id)
);
CREATE INDEX ID2CONTIG_ID ON ACH_ID2CONTIG (ID) USING BTREE;
CREATE INDEX ID2CONTIG_md5 ON ACH_ID2CONTIG (md5) USING BTREE;


DROP TABLE IF EXISTS ACH_OLD_SEED;

CREATE TABLE ACH_OLD_SEED (
_id int NOT NULL AUTO_INCREMENT,                                                   
_mtime timestamp(14) NOT NULL, 
_ctime timestamp(14) NOT NULL,
md5 varchar(32) NOT NULL,
ID varchar(32),
xxx varchar(16),
function varchar(500), 
source integer,
organism integer,
organism_group integer,
KEY (md5),
PRIMARY KEY (_id) 
);
CREATE INDEX OLD_SEED_ID ON ACH_OLD_SEED (ID) USING BTREE;
CREATE INDEX OLD_SEED_organismGroup ON ACH_OLD_SEED (organism_group) USING BTREE; 
CREATE INDEX OLD_SEED_md5 ON ACH_OLD_SEED (md5) USING BTREE;
CREATE INDEX OLD_SEED_xxx ON ACH_OLD_SEED (xxx) USING BTREE;
CREATE INDEX OLD_SEED_function ON ACH_OLD_SEED (function) USING BTREE;


DROP TABLE IF EXISTS ACH_COUNTS;

CREATE TABLE ACH_COUNTS (
_id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
type text,
count integer,
PRIMARY KEY (_id)
);
CREATE INDEX COUNTS_type ON ACH_COUNTS (type) USING BTREE;
