package Config;

$ROOT = ""; # set to path

$html_base       = $ROOT."/site/CGI/Html";
$bin             = $ROOT."/bin";
$temp            = $ROOT."/CGI/Tmp";
$incoming        = $ROOT."/incoming";
$locks           = $ROOT."/locks";
$temp_url        = "http://localhost:8080/Tmp";
$cgi_url         = "http://localhost:8080/";
$server_version  = "3.1.2";
$web_memcache    = "";

# JobDB
$mgrast_jobcache_db       = '';
$mgrast_jobcache_host     = '';
$mgrast_jobcache_user     = '';
$mgrast_jobcache_password = '';
$mgrast_v3_jobs           = '';
$mgrast_jobs              = '';
$mgrast_data              = '';
$mgrast_projects          = $ROOT."/projects";
$run_preprocess           = $ROOT."/bin/run_preprocess.sh";
$create_job               = $ROOT."/Pipeline/stages/create_and_submit_job";
$create_job_qiime         = $ROOT."/Pipeline/stages/create_job_qiime";
$seq_length_stats         = $ROOT."/bin/seq_length_stats";

$require_terms_of_service = 2;

# MetadataDB (now the same db as JobDB)
$mgrast_metadata_db       = '';
$mgrast_metadata_host     = '';
$mgrast_metadata_user     = '';
$mgrast_metadata_password = '';

# FormWiz
$mgrast_formWizard_templates = $ROOT."/src/MGRAST/Templates";

# Analysis DB 
$mgrast_db     = '';
$mgrast_dbms   = '';
$mgrast_dbuser = '';
$mgrast_dbhost = '';

# ACH settings
$babel_db     = '';
$babel_dbtype = '';
$babel_dbuser = '';
$babel_dbhost = '';

# Web Application
$webapplication_db      = 'WebAppBackend';
$webapplication_backend = 'MySQL';
$webapplication_host    = '';
$webapplication_user    = 'webapplication';
$no_prefs = 1;

$mgrast_config_dir = "$ROOT/src/MGRAST/conf";
$r_executable = "/soft/packages/R/2.11.1/bin/R";
$r_scripts = "$ROOT/src/MGRAST/r/";
$fraggenescan_executable = "/soft/packages/FragGeneScan/1.15/bin/FragGeneScan";
$run_fraggenescan = "/soft/packages/FragGeneScan/1.15/bin/run_FragGeneScan.pl";

1;