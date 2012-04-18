package FIG_Config;

$ROOT = "/Users/jared/gitprojects/MG-RAST";

$html_base       = $ROOT."/site/CGI/Html";
$bin             = $ROOT."/bin";
$temp            = $ROOT."/CGI/Tmp";
$incoming        = $ROOT."/incoming";
$locks           = $ROOT."/locks";
$temp_url        = "http://localhost:8080/Tmp";
$cgi_url         = "http://localhost:8080/";
$server_version  = "3.1.2";
$web_memcache    = "kursk-2.mcs.anl.gov:11211";

# JobDB
$mgrast_jobcache_db       = 'JobDB';
$mgrast_jobcache_host     = "kursk-3.mcs.anl.gov";
$mgrast_jobcache_user     = "mgrast";
$mgrast_jobcache_password = "";
$mgrast_v3_jobs           = "/mcs/bio/mg-rast/jobsv3";
$mgrast_jobs              = "/mcs/bio/mg-rast/jobsv3";
$mgrast_data              = "/mcs/bio/mg-rast/data";
$mgrast_projects          = $ROOT."/projects";
$run_preprocess           = $ROOT."/bin/run_preprocess.sh";
$create_job               = $ROOT."/Pipeline/stages/create_and_submit_job";
$create_job_qiime         = $ROOT."/Pipeline/stages/create_job_qiime";
$seq_length_stats         = $ROOT."/bin/seq_length_stats";

$require_terms_of_service = 2;

# MetadataDB (now the same db as JobDB)
$mgrast_metadata_db       = "JobDB";
$mgrast_metadata_host     = "kursk-3.mcs.anl.gov";
$mgrast_metadata_user     = "mgrast";
$mgrast_metadata_password = "";

# FormWiz
$mgrast_formWizard_templates = "$ROOT/src/MGRAST/Templates";

# OOD
$OOD_ontology_db        = "MG_RAST_OOD";
$OOD_ontology_dbhost    = "kursk-3.mcs.anl.gov";
$OOD_ontology_dbuser    = "mgrast";

# Analysis DB 
$mgrast_db     = "mgrast_analysis";
$mgrast_dbms   = "Pg";
$mgrast_dbuser = "mgrastprod";
$mgrast_dbhost = "kursk-3.mcs.anl.gov";

# ACH settings
$babel_db     = "mgrast_ach_prod";
$babel_dbtype = "Pg";
$babel_dbuser = "mgrastprod";
$babel_dbhost = "kursk-3.mcs.anl.gov";

# Web Application
$webapplication_db      = 'WebAppBackend';
$webapplication_backend = 'MySQL';
$webapplication_host    = 'kursk-3.mcs.anl.gov';
$webapplication_user    = 'webapplication';
$no_prefs = 1;

$mgrast_config_dir = "$ROOT/src/MGRAST/conf";
$r_executable = "/soft/packages/R/2.11.1/bin/R";
$r_scripts = "$ROOT/src/MGRAST/r/";
$fraggenescan_executable = "/soft/packages/FragGeneScan/1.15/bin/FragGeneScan";
$run_fraggenescan = "/soft/packages/FragGeneScan/1.15/bin/run_FragGeneScan.pl";

1;