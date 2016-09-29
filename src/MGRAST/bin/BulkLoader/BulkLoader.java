import java.io.*;
import java.math.BigDecimal;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.List;
import java.util.Arrays;
import java.util.ArrayList;

import com.opencsv.CSVReader;

import org.apache.cassandra.config.Config;
import org.apache.cassandra.dht.Murmur3Partitioner;
import org.apache.cassandra.exceptions.InvalidRequestException;
import org.apache.cassandra.io.sstable.CQLSSTableWriter;

public class BulkLoader {
    
    static String filename;
    static String outdir;
    static String schema;
    static String insert;
    
    public static void main(String[] args) throws IOException {
        if (args.length < 4) {
            String concat = Arrays.toString(args);
            System.out.println("Expecting 4 arguments - <keyspace>, <table>, <csv_file>, <output dir>");
            System.out.println("Got: " + concat.substring(1, concat.length() -1));
            System.exit(1);
        }
        
        int lineNumber = 0;
        long start = System.currentTimeMillis();
        String keyspace = args[0];
        String table = args[1];
        filename = args[2];
        outdir = args[3];
        
        System.out.println("keyspace: "+keyspace);
        System.out.println("table: "+table);
        System.out.println("filename: "+filename);
        System.out.println("outdir: "+outdir);
        
        // Schema and Insert for bulk load
        if (table.equals("index_annotation")) {
            schema = String.format("CREATE TABLE %s.%s (" +
                                        "id int, " +
                                        "source text, " +
                                        "md5 text, " +
                                        "is_protein boolean, " +
                                        "single int, " +
                                        "accession list<int>, " +
                                        "function list<int>, " +
                                        "organism list<int>, " +
                                        "PRIMARY KEY (id, source) " +
                                    ")", keyspace, table);
            insert = String.format("INSERT INTO %s.%s (" +
                                        "id, source, md5, is_protein, single, accession, function, organism" +
                                    ") VALUES (" +
                                        "?, ?, ?, ?, ?, ?, ?, ?" +
                                    ")", keyspace, table);
        } else if (table.equals("id_annotation")) {
            schema = String.format("CREATE TABLE %s.%s (" +
                                        "id int, " +
                                        "source text, " +
                                        "md5 text, " +
                                        "is_protein boolean, " +
                                        "single text, " +
                                        "lca list<text>, " +
                                        "accession list<text>, " +
                                        "function list<text>, " +
                                        "organism list<text>, " +
                                        "PRIMARY KEY (id, source) " +
                                    ")", keyspace, table);
            insert = String.format("INSERT INTO %s.%s (" +
                                        "id, source, md5, is_protein, single, lca, accession, function, organism" +
                                    ") VALUES (" +
                                        "?, ?, ?, ?, ?, ?, ?, ?, ?" +
                                    ")", keyspace, table);
        } else if (table.equals("midx_annotation")) {
            schema = String.format("CREATE TABLE %s.%s (" +
                                        "md5 text, " +
                                        "source text, " +
                                        "is_protein boolean, " +
                                        "single int, " +
                                        "accession list<int>, " +
                                        "function list<int>, " +
                                        "organism list<int>, " +
                                        "PRIMARY KEY (md5, source) " +
                                    ")", keyspace, table);
            insert = String.format("INSERT INTO %s.%s (" +
                                        "md5, source, is_protein, single, accession, function, organism" +
                                    ") VALUES (" +
                                        "?, ?, ?, ?, ?, ?, ?" +
                                    ")", keyspace, table);
        } else if (table.equals("md5_annotation")) {
            schema = String.format("CREATE TABLE %s.%s (" +
                                        "md5 text, " +
                                        "source text, " +
                                        "is_protein boolean, " +
                                        "single text, " +
                                        "lca list<text>, " +
                                        "accession list<text>, " +
                                        "function list<text>, " +
                                        "organism list<text>, " +
                                        "PRIMARY KEY (md5, source) " +
                                    ")", keyspace, table);
            insert = String.format("INSERT INTO %s.%s (" +
                                        "md5, source, is_protein, single, lca, accession, function, organism" +
                                    ") VALUES (" +
                                        "?, ?, ?, ?, ?, ?, ?, ?" +
                                    ")", keyspace, table);
        } else if (table.equals("job_md5s")) {
            schema = String.format("CREATE TABLE %s.%s (" +
                                        "version int, " +
                                        "job int, " +
                                        "md5 text, " +
                                        "abundance int, " +
                                        "exp_avg float, " +
                                        "ident_avg float, " +
                                        "len_avg float, " +
                                        "seek bigint, " +
                                        "length int, " +
                                        "PRIMARY KEY ((version, job), md5) " +
                                    ")", keyspace, table);
            insert = String.format("INSERT INTO %s.%s (" +
                                        "version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length" +
                                    ") VALUES (" +
                                        "?, ?, ?, ?, ?, ?, ?, ?, ?" +
                                    ")", keyspace, table);
        } else if (table.equals("job_features")) {
            schema = String.format("CREATE TABLE %s.%s (" +
                                        "version int, " +
                                        "job int, " +
                                        "md5 text, " +
                                        "feature text, " +
                                        "exp int, " +
                                        "ident int, " +
                                        "len int, " +
                                        "md5_idx int, " +
                                        "PRIMARY KEY ((version, job), md5, feature) " +
                                    ")", keyspace, table);
            insert = String.format("INSERT INTO %s.%s (" +
                                        "version, job, md5, feature, exp, ident, len, md5_idx" +
                                    ") VALUES (" +
                                        "?, ?, ?, ?, ?, ?, ?, ?" +
                                    ")", keyspace, table);
        } else {
            System.out.println("Unsupported table type: " + table);
            System.exit(1);
        }
        
        // magic!
        Config.setClientMode(true);
        
        // Create output directory that has keyspace and table name in the path
        File outputDir = new File(outdir + File.separator + keyspace + File.separator + table);
        if (!outputDir.exists() && !outputDir.mkdirs()) {
            throw new RuntimeException("Cannot create output directory: " + outputDir);
        }
        
        // Prepare SSTable writer
        CQLSSTableWriter.Builder builder = CQLSSTableWriter.builder();
        // set output directory
        builder.inDirectory(outputDir)
            // set target schema
            .forTable(schema)
            // set CQL statement to put data
            .using(insert)
            // set partitioner if needed - default is Murmur3Partitioner so set if you use different one.
            .withPartitioner(new Murmur3Partitioner());
        CQLSSTableWriter writer = builder.build();
        
        // set cvs reader / parser
        try (
            CSVReader csvReader = new CSVReader(new FileReader(filename));
        ) {
            // Write to SSTable while reading data
            String[] line;
            while ((line = csvReader.readNext()) != null) {
                // We use Java types here based on
                // http://www.datastax.com/drivers/java/2.0/com/datastax/driver/core/DataType.Name.html#asJavaClass%28%29
                if (table.equals("index_annotation")) {
                    writer.addRow(Integer.parseInt(line[0]),
                                  line[1],
                                  line[2],
                                  Boolean.valueOf(line[3]),
                                  Integer.parseInt(line[4]),
                                  parseIntList(line[5]),
                                  parseIntList(line[6]),
                                  parseIntList(line[7]));
                } else if (table.equals("id_annotation")) {
                    writer.addRow(Integer.parseInt(line[0]),
                                  line[1],
                                  line[2],
                                  Boolean.valueOf(line[3]),
                                  line[4],
                                  parseStringList(line[5]),
                                  parseStringList(line[6]),
                                  parseStringList(line[7]),
                                  parseStringList(line[8]));
                } else if (table.equals("midx_annotation")) {
                    writer.addRow(line[0]),
                                  line[1],
                                  Boolean.valueOf(line[2]),
                                  Integer.parseInt(line[3]),
                                  parseIntList(line[4]),
                                  parseIntList(line[5]),
                                  parseIntList(line[6]));
                } else if (table.equals("md5_annotation")) {
                    writer.addRow(line[0],
                                  line[1],
                                  Boolean.valueOf(line[2]),
                                  line[3],
                                  parseStringList(line[4]),
                                  parseStringList(line[5]),
                                  parseStringList(line[6]),
                                  parseStringList(line[7]));
                } else if (table.equals("job_md5s")) {
                    writer.addRow(Integer.parseInt(line[0]),
                                  Integer.parseInt(line[1]),
                                  line[2],
                                  Integer.parseInt(line[3]),
                                  Float.parseFloat(line[4]),
                                  Float.parseFloat(line[5]),
                                  Float.parseFloat(line[6]),
                                  Long.parseLong(line[7]),
                                  Integer.parseInt(line[8]));
                } else if (table.equals("job_features")) {
                    writer.addRow(Integer.parseInt(line[0]),
                                  Integer.parseInt(line[1]),
                                  line[2],
                                  line[3],
                                  Integer.parseInt(line[4]),
                                  Integer.parseInt(line[5]),
                                  Integer.parseInt(line[6]),
                                  Integer.parseInt(line[7]));
                }
                // Print nK
                lineNumber += 1;
                if (lineNumber % 10000 == 0) {
                    System.out.println((lineNumber / 1000) + "K");
                }
            }
        } catch (InvalidRequestException | IOException e) {
            e.printStackTrace();
        }
        
        try {
            writer.close();
        } catch (IOException ignore) {}
        
        // done
        long end = System.currentTimeMillis();
        System.out.println("Successfully parsed " + lineNumber + " lines.");
        System.out.println("Execution time was " + ((end-start) / 1000) + " seconds.");
        System.exit(0);
    }
    
    public static List<String> parseStringList (String listStr) {
        List<String> aList = new ArrayList<String>();
        listStr = listStr.trim();
        if (listStr.isEmpty()) {
            return aList;
        }
        // remove leading and trailing brackets
        listStr = listStr.substring(1, listStr.length() - 1).trim();
        if (listStr.isEmpty()) {
            return aList;
        }
        // split by comma
        String[] parts = listStr.split(",");
        for (int i=0; i<parts.length; i++) {
            // add to list, remove leading and trailing single-quotes
            String item = parts[i].trim();
            if (item.length() > 1) {
                aList.add( item.substring(1, item.length() - 1).trim() );
            } else {
                aList.add( new String() );
            }
        }
        return aList;
    }
    
    public static List<Integer> parseIntList (String listStr) {
        List<Integer> aList = new ArrayList<Integer>();
        listStr = listStr.trim();
        if (listStr.isEmpty()) {
            return aList;
        }
        // remove leading and trailing brackets
        listStr = listStr.substring(1, listStr.length() - 1).trim();
        if (listStr.isEmpty()) {
            return aList;
        }
        // split by comma
        String[] parts = listStr.split(",");
        for (int i=0; i<parts.length; i++) {
            // cast to int, add to list
            String item = parts[i].trim();
            aList.add( Integer.parseInt(item) );
        }
        return aList;
    }
    
}
