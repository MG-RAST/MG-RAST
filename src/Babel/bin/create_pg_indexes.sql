CREATE UNIQUE INDEX md5s_md5 ON md5s (md5);
CREATE INDEX md5s_protein ON md5s (is_protein);

CREATE INDEX md5_protein_id ON md5_protein (id);
CREATE INDEX md5_protein_md5 ON md5_protein (md5);
CREATE INDEX md5_protein_function ON md5_protein (function);
CREATE INDEX md5_protein_organism ON md5_protein (organism);
CREATE INDEX md5_protein_source ON md5_protein (source);

CREATE INDEX md5_ontology_id ON md5_ontology (id);
CREATE INDEX md5_ontology_md5 ON md5_ontology (md5);
CREATE INDEX md5_ontology_function ON md5_ontology (function);
CREATE INDEX md5_ontology_source ON md5_ontology (source);

CREATE INDEX md5_rna_id ON md5_rna (id);
CREATE INDEX md5_rna_md5 ON md5_rna (md5);
CREATE INDEX md5_rna_function ON md5_rna (function);
CREATE INDEX md5_rna_organism ON md5_rna (organism);
CREATE INDEX md5_rna_tax_rank ON md5_rna (tax_rank);
CREATE INDEX md5_rna_source ON md5_rna (source);

CREATE INDEX md5_organism_unique_md5 ON md5_organism_unique (md5);
CREATE INDEX md5_organism_unique_source ON md5_organism_unique (source);

CREATE INDEX aliases_protein_id on aliases_protein (id);

CREATE INDEX functions_name ON functions (name);

CREATE INDEX contigs_id ON contigs (name);
CREATE INDEX contigs_organism ON contigs (organism);
CREATE INDEX contigs_length ON contigs (length);

CREATE INDEX id2contig_id ON id2contig (id);
CREATE INDEX id2contig_contig ON id2contig (contig);

CREATE INDEX organisms_ncbi_name ON organisms_ncbi (name);
CREATE INDEX organisms_ncbi_tax_id ON organisms_ncbi (ncbi_tax_id);

CREATE INDEX ontology_seed_id ON ontology_seed (id);
CREATE INDEX ontology_kegg_id ON ontology_kegg (id);
CREATE INDEX ontology_eggnog_id ON ontology_eggnog (id);
CREATE INDEX ontology_eggnog_type ON ontology_eggnog (type);

CREATE INDEX ontologies_id ON ontologies (id);
CREATE INDEX ontologies_type ON ontologies (source);

CREATE INDEX sources_name ON sources (name);
CREATE INDEX sources_type ON sources (type);

/* load ontologies table */
INSERT INTO ontologies (level1,level2,level3,level4,id,source) SELECT level1,level2,level3,level4,id,12 FROM ontology_kegg;
INSERT INTO ontologies (level1,level2,level3,level4,id,source) SELECT level1,level2,level3,level4,id,14 FROM ontology_seed;
INSERT INTO ontologies (level1,level2,level3,id,source) SELECT level1,level2,level3,id,10 FROM ontology_eggnog WHERE type='COG';
INSERT INTO ontologies (level1,level2,level3,id,source) SELECT level1,level2,level3,id,13 FROM ontology_eggnog WHERE type='NOG';

