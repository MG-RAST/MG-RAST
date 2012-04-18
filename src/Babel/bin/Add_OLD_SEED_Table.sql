
CREATE TABLE ACH_OLD_SEED ( _id int NOT NULL AUTO_INCREMENT,                                                   
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
CREATE INDEX OLD_SEED_id ON ACH_OLD_SEED (id);                                                                     
CREATE INDEX OLD_SEED_organismGroup ON ACH_OLD_SEED (organism_group);
CREATE INDEX OLD_SEED_md5 ON ACH_OLD_SEED (md5);


