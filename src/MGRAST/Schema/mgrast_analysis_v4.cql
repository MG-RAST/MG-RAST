
CREATE KEYSPACE IF NOT EXISTS mgrast_analysis
    WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 2 };

use mgrast_analysis;

CREATE TYPE source_info (
    accession list<text>,
    function list<text>,
    organism list<text>
);

CREATE TYPE md5_info (
    abundance int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    exp_stdv float,
    ident_stdv float,
    len_stdv float,
    seek bigint,
    length int,
    is_protein boolean
);

CREATE TYPE lca_info (
    abundance int,
    md5s int,
    level int
);

CREATE TABLE job_test (
    version int,
    job int,
    exp_avg float,
    md5 text,
    data text,
    PRIMARY KEY ((version, job), exp_avg, md5)
);
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 10, 50, 'foo', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 10, 50, 'bar', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 10, 60, 'foo', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 10, 70, 'foo', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 10, 70, 'bar', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 20, 50, 'foo', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 20, 50, 'bar', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 20, 60, 'foo', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 20, 70, 'foo', 'hello world');
INSERT INTO job_test (version, job, exp_avg, md5, data) VALUES (1, 20, 70, 'bar', 'hello world');

### version 1 ###
CREATE TABLE IF NOT EXISTS job_md5s (
    version int,
    job int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    exp_stdv float,
    ident_stdv float,
    len_stdv float,
    md5s map<text, frozen <md5_info>>,
    PRIMARY KEY ((version, job), exp_avg, ident_avg, len_avg)
);

CREATE TABLE IF NOT EXISTS job_lcas (
    version int,
    job int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    exp_stdv float,
    ident_stdv float,
    len_stdv float,
    lcas map<text, frozen <lca_info>>,
    PRIMARY KEY ((version, job), exp_avg, ident_avg, len_avg)
);

# see: http://docs.datastax.com/en/cql/3.1/cql/cql_using/use-slice-partition.html

### version 2 ###
CREATE TABLE IF NOT EXISTS job_md5s (
    version int,
    job int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    md5 text,
    exp_stdv float,
    ident_stdv float,
    len_stdv float,
    abundance int,
    seek bigint,
    length int,
    is_protein boolean,
    accession map<text, frozen<list<text>>>,
    function map<text, frozen<list<text>>>,
    organism map<text, frozen<list<text>>>,
    PRIMARY KEY ((version, job), exp_avg, ident_avg, len_avg, md5)
) WITH CLUSTERING ORDER BY (exp_avg DESC, ident_avg DESC, len_avg DESC);
COPY job_md5s (version, job, exp_avg, ident_avg, len_avg, md5, exp_stdv, ident_stdv, len_stdv, abundance, seek, length, is_protein, accession, function, organism) FROM '/mnt/src/job_data.1595';

CREATE TABLE IF NOT EXISTS job_lcas (
    version int,
    job int,
    exp_avg float,
    ident_avg float,
    len_avg float,
    lca text,
    exp_stdv float,
    ident_stdv float,
    len_stdv float,
    abundance int,
    md5s int,
    level int,
    PRIMARY KEY ((version, job), exp_avg, ident_avg, len_avg, lca)
);

### version 3 ###
CREATE TABLE IF NOT EXISTS job_md5s (
    version int,
    job int,
    source text,
    md5 text,
    data frozen<md5_info>,
    accession list<text>,
    function list<text>,
    organism list<text>,
    PRIMARY KEY ((version, job), source, md5)
);
    

