
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

CREATE TABLE IF NOT EXISTS job_reads (
    version int,
    job int,
    md5 text,
    read int,
    abundance int,
    exp int,
    ident int,
    len int,
    sim int,
    PRIMARY KEY ((version, job), md5, read)
);

CREATE INDEX job_reads_exp_idx ON job_reads (exp);
CREATE INDEX job_reads_ident_idx ON job_reads (ident);
CREATE INDEX job_reads_len_idx ON job_reads (len);

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

