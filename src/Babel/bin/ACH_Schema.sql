use ACH_TEST;

DROP TABLE IF EXISTS ACH_ID2GROUP;

CREATE TABLE ACH_ID2GROUP ( _id int NOT NULL AUTO_INCREMENT,                                                   
_mtime timestamp(14) NOT NULL, 
_ctime timestamp(14) NOT NULL,
md5 varchar(32) NOT NULL,
ID varchar(32), 
function varchar(500), 
source integer,
organism integer,
organism_group integer,
KEY (md5),
PRIMARY KEY (_id) 
);
CREATE INDEX ID2GROUP_id ON ACH_ID2GROUP (id);                                                                     
CREATE INDEX ID2GROUP_organismGroup ON ACH_ID2GROUP (organism_group);
CREATE INDEX ID2GROUP_md5 ON ACH_ID2GROUP (md5);




DROP TABLE IF EXISTS ACH_DATA;

CREATE TABLE ACH_DATA ( _id int NOT NULL AUTO_INCREMENT,                                                   
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
CREATE INDEX DATA_ID ON ACH_DATA (ID); 
CREATE INDEX DATA_organism ON ACH_DATA (organism);	                                                                    
CREATE INDEX DATA_organismGroup ON ACH_DATA (organism_group); 
CREATE INDEX DATA_md5 ON ACH_DATA (md5);


DROP TABLE IF EXISTS ACH_FUNCTIONS;

CREATE TABLE ACH_FUNCTIONS ( _id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
function  text,

KEY (function(300)),
PRIMARY KEY (_id)
);



DROP TABLE IF EXISTS ACH_SOURCES;

CREATE TABLE ACH_SOURCES ( _id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
name  text,
email text,
type  text,
link  text,

KEY (name(100)),
PRIMARY KEY (_id)
);



DROP TABLE IF EXISTS ACH_ORGANISMS;

CREATE TABLE ACH_ORGANISMS ( _id int NOT NULL AUTO_INCREMENT,                                                   
_mtime timestamp(14) NOT NULL, 
_ctime timestamp(14) NOT NULL,
name text  NOT NULL,
domain text,
level2 text,
level3 text,
taxonomy text,
ncbi_tax_id int ,
organism_group integer,
PRIMARY KEY (_id) 
);
CREATE INDEX ORGANISMS_name ON ACH_ORGANISMS (name (100) );


DROP TABLE IF EXISTS ACH_ID2CONTIG;

CREATE TABLE ACH_ID2CONTIG ( _id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
ID  varchar(32),
contigID varchar(32),
contigLength integer,
strand  integer,
low  integer,
high integer,
md5 varchar(32),
KEY (ID),
PRIMARY KEY (_id)
);

