
CREATE KEYSPACE IF NOT EXISTS m5nr_v1
    WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 2 };

use m5nr_v1;

CREATE TABLE IF NOT EXISTS md5_id_annotation (
    id int,
    source text,
    md5 text,
    is_protein boolean,
    single text,
    lca list<text>,
    accession list<text>,
    function list<text>,
    organism list<text>,
    PRIMARY KEY (id, source)
);
COPY md5_id_annotation (id, source, md5, is_protein, single, lca, accession, function, organism) FROM '/mnt/src/m5nr_v1.annotation.id';

CREATE TABLE IF NOT EXISTS md5_annotation (
    md5 text,
    source text,
    is_protein boolean,
    single text,
    lca text,
    accession list<text>,
    function list<text>,
    organism list<text>,
    PRIMARY KEY (md5, source)
);
COPY md5_annotation (md5, source, is_protein, single, lca, accession, function, organism) FROM '/mnt/src/m5nr_v1.annotation.md5';

CREATE TABLE IF NOT EXISTS ontologies (
    source text,
    name text,
    level1 text,
    level2 text,
    level3 text,
    level4 text,
    PRIMARY KEY (source, name)
);
COPY ontologies (source, name, level1, level2, level3, level4) FROM '/mnt/src/m5nr_v1.ontology.all';

CREATE TABLE IF NOT EXISTS ont_level1 (
    source text,
    level1 text,
    name text,
    PRIMARY KEY (source, level1, name)
);
COPY ont_level1 (source, level1, name) FROM '/mnt/src/m5nr_v1.ontology.level1';

CREATE TABLE IF NOT EXISTS ont_level2 (
    source text,
    level2 text,
    name text,
    PRIMARY KEY (source, level2, name)
);
COPY ont_level2 (source, level2, name) FROM '/mnt/src/m5nr_v1.ontology.level2';

CREATE TABLE IF NOT EXISTS ont_level3 (
    source text,
    level3 text,
    name text,
    PRIMARY KEY (source, level3, name)
);
COPY ont_level3 (source, level3, name) FROM '/mnt/src/m5nr_v1.ontology.level3';

CREATE TABLE IF NOT EXISTS ont_level4 (
    source text,
    level4 text,
    name text,
    PRIMARY KEY (source, level4, name)
);
COPY ont_level4 (source, level4, name) FROM '/mnt/src/m5nr_v1.ontology.level4';

CREATE TABLE IF NOT EXISTS organisms_ncbi (
    name text,
    tax_domain text,
    tax_phylum text,
    tax_class text,
    tax_order text,
    tax_family text,
    tax_genus text,
    tax_species text,
    ncbi_tax_id int,
    PRIMARY KEY (name)
);
COPY organisms_ncbi (name, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, ncbi_tax_id) FROM '/mnt/src/m5nr_v1.taxonomy.all';

CREATE TABLE IF NOT EXISTS tax_domain (
    tax_domain text,
    name text,
    PRIMARY KEY (tax_domain, name)
);
COPY tax_domain (tax_domain, name) FROM '/mnt/src/m5nr_v1.taxonomy.domain';

CREATE TABLE IF NOT EXISTS tax_phylum (
    tax_phylum text,
    name text,
    PRIMARY KEY (tax_phylum, name)
);
COPY tax_phylum (tax_phylum, name) FROM '/mnt/src/m5nr_v1.taxonomy.phylum';

CREATE TABLE IF NOT EXISTS tax_class (
    tax_class text,
    name text,
    PRIMARY KEY (tax_class, name)
);
COPY tax_class (tax_class, name) FROM '/mnt/src/m5nr_v1.taxonomy.class';

CREATE TABLE IF NOT EXISTS tax_order (
    tax_order text,
    name text,
    PRIMARY KEY (tax_order, name)
);
COPY tax_order (tax_order, name) FROM '/mnt/src/m5nr_v1.taxonomy.order';

CREATE TABLE IF NOT EXISTS tax_family (
    tax_family text,
    name text,
    PRIMARY KEY (tax_family, name)
);
COPY tax_family (tax_family, name) FROM '/mnt/src/m5nr_v1.taxonomy.family';

CREATE TABLE IF NOT EXISTS tax_genus (
    tax_genus text,
    name text,
    PRIMARY KEY (tax_genus, name)
);
COPY tax_genus (tax_genus, name) FROM '/mnt/src/m5nr_v1.taxonomy.genus';

CREATE TABLE IF NOT EXISTS tax_species (
    tax_species text,
    name text,
    PRIMARY KEY (tax_species, name)
);
COPY tax_species (tax_species, name) FROM '/mnt/src/m5nr_v1.taxonomy.species';
