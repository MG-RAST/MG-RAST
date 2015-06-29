import java.io.*;
import java.math.BigDecimal;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.List;
import java.util.Arrays;
import java.util.ArrayList;

import org.supercsv.io.CsvListReader;
import org.supercsv.prefs.CsvPreference;

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
        if (table.equals("md5_id_annotation")) {
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
            BufferedReader reader = new BufferedReader(new FileReader(filename));
            CsvListReader csvReader = new CsvListReader(reader, CsvPreference.STANDARD_PREFERENCE);
        ) {
            csvReader.getHeader(true); // skip the header
        
            // Write to SSTable while reading data
            List<String> line;
            while ((line = csvReader.read()) != null) {
                // We use Java types here based on
                // http://www.datastax.com/drivers/java/2.0/com/datastax/driver/core/DataType.Name.html#asJavaClass%28%29
                if (table.equals("md5_id_annotation")) {
                    writer.addRow(Integer.parseInt(line.get(0)),
                                  line.get(1),
                                  line.get(2),
                                  Boolean.valueOf(line.get(3)),
                                  line.get(4),
                                  parseList(line.get(5)),
                                  parseList(line.get(6)),
                                  parseList(line.get(7)),
                                  parseList(line.get(8)));
                } else if (table.equals("md5_annotation")) {
                    writer.addRow(line.get(0),
                                  line.get(1),
                                  Boolean.valueOf(line.get(2)),
                                  line.get(3),
                                  parseList(line.get(4)),
                                  parseList(line.get(5)),
                                  parseList(line.get(6)),
                                  parseList(line.get(7)));
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
    
    public static List<String> parseList (String listStr) {
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
    
}
