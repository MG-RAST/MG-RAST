
CREATE KEYSPACE IF NOT EXISTS mgrast_analysis
    WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 4 };

use mgrast_analysis;

CREATE TABLE IF NOT EXISTS job_info (
    version int,
    job int,
    updated_on timestamp,
    md5s int,
    PRIMARY KEY ((version, job), updated_on)
);

CREATE TABLE IF NOT EXISTS job_md5s (
    version int,
    job int,
    md5 text,
    abundance int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    seek bigint,
    length int,
    PRIMARY KEY ((version, job), md5)
);

CREATE INDEX job_md5s_exp_idx ON job_md5s (exp_avg);
CREATE INDEX job_md5s_ident_idx ON job_md5s (ident_avg);
CREATE INDEX job_md5s_len_idx ON job_md5s (len_avg);

CREATE TABLE IF NOT EXISTS job_features (
    version int,
    job int,
    md5 text,
    feature text,
    exp int,
    ident int,
    len int,
    md5_idx int,
    PRIMARY KEY ((version, job), md5, feature)
);

CREATE INDEX job_features_exp_idx ON job_features (exp);
CREATE INDEX job_features_ident_idx ON job_features (ident);
CREATE INDEX job_features_len_idx ON job_features (len);

CREATE TABLE IF NOT EXISTS job_lcas (
    version int,
    job int,
    lca text,
    abundance int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    md5s int,
    level int,
    PRIMARY KEY ((version, job), lca)
);

CREATE INDEX job_lcas_exp_idx ON job_lcas (exp_avg);
CREATE INDEX job_lcas_ident_idx ON job_lcas (ident_avg);
CREATE INDEX job_lcas_len_idx ON job_lcas (len_avg);

