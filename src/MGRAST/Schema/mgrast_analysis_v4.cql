
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
    seek bigint,
    length int,
    annotation map<text, frozen <source_info>>
);

CREATE TYPE lca_info (
    abundance int,
    md5s int,
    level int
);

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
);
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

