
import cass_connection
import cassandra.query as cql

class M5nrUpload(object):
    def __init__(self, hosts, version):
        self.keyspace = "m5nr_v"+str(version)
        self.session = cass_connection.create(hosts).connect()
        self.session.default_timeout = 300
        self.inserts = {
            "annotation.midx"  : "INSERT INTO midx_annotation (md5, source, is_protein, single, accession, function, organism) VALUES (?, ?, ?, ?, ?, ?, ?)",
            "annotation.md5"   : "INSERT INTO md5_annotation (md5, source, is_protein, single, lca, accession, function, organism) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            "functions"        : "INSERT INTO functions (id, name) VALUES (?, ?)",
            "ontology.all"     : "INSERT INTO ontologies (source, name, level1, level2, level3, level4) VALUES (?, ?, ?, ?, ?, ?)",
            "ontology.level1"  : "INSERT INTO ont_level1 (source, level1, name) VALUES (?, ?, ?)",
            "ontology.level2"  : "INSERT INTO ont_level2 (source, level2, name) VALUES (?, ?, ?)",
            "ontology.level3"  : "INSERT INTO ont_level3 (source, level3, name) VALUES (?, ?, ?)",
            "ontology.level4"  : "INSERT INTO ont_level4 (source, level4, name) VALUES (?, ?, ?)",
            "taxonomy.all"     : "INSERT INTO organisms_ncbi (name, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, ncbi_tax_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            "taxonomy.domain"  : "INSERT INTO tax_domain (tax_domain, name) VALUES (?, ?)",
            "taxonomy.phylum"  : "INSERT INTO tax_phylum (tax_phylum, name) VALUES (?, ?)",
            "taxonomy.class"   : "INSERT INTO tax_class (tax_class, name) VALUES (?, ?)",
            "taxonomy.order"   : "INSERT INTO tax_order (tax_order, name) VALUES (?, ?)",
            "taxonomy.family"  : "INSERT INTO tax_family (tax_family, name) VALUES (?, ?)",
            "taxonomy.genus"   : "INSERT INTO tax_genus (tax_genus, name) VALUES (?, ?)",
            "taxonomy.species" : "INSERT INTO tax_species (tax_species, name) VALUES (?, ?)"
        }

    def close(self):
        cass_connection.destroy()
    
    def batchInsert(self, table, data):
        self.session.set_keyspace(self.keyspace)
        
        # fix booleans
        if (table == "annotation.midx") or ($table == "annotation.md5"):
            for i in range(len(data)):
                data[i][2] = True if data[i][2] == 1 else False
        
        cmd = self.inserts[table]
        insert = self.session.prepare(cmd)
        batch  = cql.BatchStatement(consistency_level=cql.ConsistencyLevel.QUORUM)
        for row in data:
            batch.add(insert, tuple(row))
        try:
            self.session.execute(batch)
        except:
            return "unable to insert data: an exception of type {0} occured. Arguments:\n{1!r}".format(type(ex).__name__, ex.args)
        return ""
    
    def createNewM5nr(self):
        rows = self.session.execute("SELECT keyspace_name FROM system_schema.keyspaces")
        if self.keyspace in [row[0] for row in rows]:
            return "unable to complete: a keyspace already exists for the given M5NR version number"
        
        try:
            # create keyspace
            self.session.execute("""
                CREATE KEYSPACE IF NOT EXISTS %s
                WITH replication = { 'class': 'SimpleStrategy', 'replication_factor': '3' }
                """ %(self.keyspace)
            )
            self.session.set_keyspace(self.keyspace)
        except:
            return "unable to create keyspace: an exception of type {0} occured. Arguments:\n{1!r}".format(type(ex).__name__, ex.args)
        
        try:    
            # create tables
            self.session.execute("""
            CREATE TABLE IF NOT EXISTS midx_annotation (
                md5 text,
                source text,
                is_protein boolean,
                single int,
                accession list<text>,
                function list<int>,
                organism list<int>,
                PRIMARY KEY (md5, source)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS md5_annotation (
                md5 text,
                source text,
                is_protein boolean,
                single text,
                lca list<text>,
                accession list<text>,
                function list<text>,
                organism list<text>,
                PRIMARY KEY (md5, source)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS functions (
                id int,
                name text,
                PRIMARY KEY (id)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS ontologies (
                source text,
                name text,
                level1 text,
                level2 text,
                level3 text,
                level4 text,
                PRIMARY KEY (source, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS ont_level1 (
                source text,
                level1 text,
                name text,
                PRIMARY KEY (source, level1, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS ont_level2 (
                source text,
                level2 text,
                name text,
                PRIMARY KEY (source, level2, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS ont_level3 (
                source text,
                level3 text,
                name text,
                PRIMARY KEY (source, level3, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS ont_level4 (
                source text,
                level4 text,
                name text,
                PRIMARY KEY (source, level4, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
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
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_domain (
                tax_domain text,
                name text,
                PRIMARY KEY (tax_domain, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_phylum (
                tax_phylum text,
                name text,
                PRIMARY KEY (tax_phylum, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_class (
                tax_class text,
                name text,
                PRIMARY KEY (tax_class, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_order (
                tax_order text,
                name text,
                PRIMARY KEY (tax_order, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_family (
                tax_family text,
                name text,
                PRIMARY KEY (tax_family, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_genus (
                tax_genus text,
                name text,
                PRIMARY KEY (tax_genus, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)

            self.session.execute("""
            CREATE TABLE IF NOT EXISTS tax_species (
                tax_species text,
                name text,
                PRIMARY KEY (tax_species, name)
            )
            WITH compaction = { 'class': 'LeveledCompactionStrategy' };
            """)
        except Exception as ex:
            return "unable to create tables: an exception of type {0} occured. Arguments:\n{1!r}".format(type(ex).__name__, ex.args)
        return ""

