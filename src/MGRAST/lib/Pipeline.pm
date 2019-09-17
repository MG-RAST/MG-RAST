package Pipeline;

use strict;
use warnings;
no warnings('once');

use Conf;
use DBI;
use JSON;
use Template;
use Data::Dumper;
use File::Slurp;

our $priority_map = {
    "never"       => 1,
    "date"        => 5,
    "6months"     => 10,
    "3months"     => 15,
    "immediately" => 20
};

our $json = JSON->new();
$json->max_size(0);
$json->allow_nonref;

sub populate_template {
    my ($jobj, $jattr, $jopts, $vars, $input_id, $version, $use_docker) = @_;

    # set template
    my $tpage = Template->new(ABSOLUTE => 1);
    my $template = $Conf::workflow_dir."/mgrast-prod-".$version.".awf";
    my $template_str = read_file($template);

    # populate workflow variables
    my $job_id = $jobj->{job_id};
    if ($use_docker) {
    	$vars->{docker_switch} = '';
    } else {
    	$vars->{docker_switch} = '_'; # disables these entries
    }
    $vars->{job_id}         = $job_id;
    $vars->{mg_id}          = 'mgm'.$jobj->{metagenome_id};
    $vars->{mg_name}        = $jobj->{name};
    $vars->{job_date}       = $jobj->{created_on};
    $vars->{file_format}    = ($jattr->{file_type} && ($jattr->{file_type} eq 'fastq')) ? 'fastq' : 'fasta';
    $vars->{seq_type}       = $jobj->{sequence_type} || $jattr->{sequence_type_guess};
    $vars->{user}           = 'mgu'.$jobj->{owner} || '';
    $vars->{shock_node}     = $input_id;
    $vars->{inputfile}      = $jobj->{file} || $job_id.'.050.upload.'.(($vars->{file_format} eq 'fastq') ? 'fastq' : 'fna');
    $vars->{filter_options} = $jopts->{filter_options} || 'skip';
    $vars->{assembled}      = exists($jattr->{assembled}) ? $jattr->{assembled} : 0;
    $vars->{dereplicate}    = exists($jopts->{dereplicate}) ? $jopts->{dereplicate} : 1;
    $vars->{bowtie}         = exists($jopts->{bowtie}) ? $jopts->{bowtie} : 1;
    $vars->{screen_indexes} = exists($jopts->{screen_indexes}) ? $jopts->{screen_indexes} : 'h_sapiens';
    $vars->{screen_indexes} = validate_indexes($vars->{screen_indexes});
    $vars->{project_id}     = "";
    $vars->{project_name}   = "";
    # is hash
    if ($jobj->{project_id} && $jobj->{project_name}) {
        $vars->{project_id}   = 'mgp'.$jobj->{project_id};
        $vars->{project_name} = $jobj->{project_name};
    }
    # is object
    elsif ($jobj->{primary_project}) {
        eval {
            my $proj = $jobj->primary_project;
	        if ($proj->{id}) {
	            $vars->{project_id}   = "mgp".$proj->{id};
	            $vars->{project_name} = $proj->{name};
            }
        };
    }
    # set node output type for preprocessing
    if ($vars->{file_format} eq 'fastq') {
        $vars->{preprocess_pass} = qq(,
                        "shockindex": "record");
        $vars->{preprocess_fail} = "";
    } elsif ($vars->{filter_options} eq 'skip') {
        $vars->{preprocess_pass} = qq(,
                        "type": "copy",
                        "formoptions": {
                            "parent_name": "${job_id}.080.adapter.trim.passed.).$vars->{file_format}.qq(",
                            "copy_indexes": "1"
                        });
        $vars->{preprocess_fail} = "";
    } else {
        $vars->{preprocess_pass} = qq(,
                        "type": "subset",
                        "formoptions": {
                            "parent_name": "${job_id}.080.adapter.trim.passed.).$vars->{file_format}.qq(",
                            "parent_index": "record"
                        });
        $vars->{preprocess_fail} = $vars->{preprocess_pass};
    }
    # set node output type for dereplication
    if ($vars->{dereplicate} == 0) {
        $vars->{dereplicate_pass} = qq(,
                        "type": "copy",
                        "formoptions": {
                            "parent_name": "${job_id}.100.preprocess.passed.fna",
                            "copy_indexes": "1"
                        });
        $vars->{dereplicate_fail} = "";
    } else {
        $vars->{dereplicate_pass} = qq(,
                        "type": "subset",
                        "formoptions": {
                            "parent_name": "${job_id}.100.preprocess.passed.fna",
                            "parent_index": "record"
                        });
        $vars->{dereplicate_fail} = $vars->{dereplicate_pass};
    }
    # set node output type for bowtie
    if ($vars->{bowtie} == 0) {
        $vars->{bowtie_pass} = qq(,
                        "type": "copy",
                        "formoptions": {
                            "parent_name": "${job_id}.150.dereplication.passed.fna",
                            "copy_indexes": "1"
                        });
    } else {
        $vars->{bowtie_pass} = qq(,
                        "type": "subset",
                        "formoptions": {
                            "parent_name": "${job_id}.150.dereplication.passed.fna",
                            "parent_index": "record"
                        });
    }
    # build bowtie index list
    my $bowtie_url = $Conf::shock_url;
    my $bowtie_indexes = bowtie_indexes();
    $vars->{index_download_urls} = "";
    foreach my $idx (split(/,/, $vars->{screen_indexes})) {
        if (exists $bowtie_indexes->{$idx}) {
            while (my ($ifile, $inode) = each %{$bowtie_indexes->{$idx}}) {
                $vars->{index_download_urls} .= qq(
                    "$ifile": {
                        "url": "${bowtie_url}/node/${inode}?download"
                    },);
            }
        }
    }
    chop $vars->{index_download_urls};

    # replace variables (reads from $template_str and writes to $workflow_str)
    my $workflow_obj = undef;
    my $workflow_str = "";
    eval {
        $tpage->process(\$template_str, $vars, \$workflow_str);
        $workflow_obj = $json->decode($workflow_str);
    };
    return $workflow_obj;
}

sub set_priority {
    my ($bp_count, $priority) = @_;

    my $pnum = 1;
    if ($priority && exists($priority_map->{$priority})) {
        $pnum = $priority_map->{$priority};
    }
    # higher priority if smaller data
    if (int($bp_count) < 100000000) {
        $pnum = 30;
    }
    if (int($bp_count) < 50000000) {
        $pnum = 40;
    }
    if (int($bp_count) < 10000000) {
        $pnum = 50;
    }
    return $pnum;
}

sub get_jobcache_dbh {
    my ($host, $name, $user, $pass, $key, $cert, $ca) = @_;
    my $conn_str = "DBI:mysql:database=".$name.";host=".$host;
    if ($key && $cert && $ca) {
        $conn_str .= ";mysql_ssl=1;mysql_ssl_client_key=".$key.";mysql_ssl_client_cert=".$cert.";mysql_ssl_ca_file=".$ca;
    }
    my $dbh = DBI->connect($conn_str, $user, $pass, { mysql_auto_reconnect => 1 }) || die $DBI::errstr;
    return $dbh;
}

sub get_jobcache_info {
    my ($dbh, $job) = @_;
    my $query = $dbh->prepare(qq(select * from Job where job_id=?));
    $query->execute($job);
    my $data = $query->fetchrow_hashref;
    if ($data->{primary_project}) {
        my $pquery = $dbh->prepare(qq(select * from Project where _id=?));
        $pquery->execute($data->{primary_project});
        my $pdata = $pquery->fetchrow_hashref;
        if ($pdata->{name} && $pdata->{id}) {
            $data->{project_name} = $pdata->{name};
            $data->{project_id} = $pdata->{id};
        }
    }
    return $data;
}

sub set_jobcache_info {
    my ($dbh, $job, $col, $val) = @_;
    my $query = $dbh->prepare(qq(update Job set $col=? where job_id=?));
    $query->execute($val, $job) or die $dbh->errstr;
}

sub get_job_attributes {
    my ($dbh, $jobid) = @_;
    return get_job_tag_data($dbh, $jobid, "JobAttributes");
}

sub get_job_statistics {
    my ($dbh, $jobid) = @_;
    return get_job_tag_data($dbh, $jobid, "JobStatistics");
}

sub get_job_options {
    my ($options) = @_;
    my $jopts = {};
    foreach my $opt (split(/\&/, $options)) {
        if ($opt =~ /^filter_options=(.*)/) {
            $jopts->{filter_options} = $1 || 'skip';
        } else {
            my ($k, $v) = split(/=/, $opt);
            $jopts->{$k} = $v;
        }
    }
    return $jopts;
}

sub get_job_tag_data {
    my ($dbh, $jobid, $table) = @_;
    my $data  = {};
    my $query = "select tag, value from $table where job=(select _id from Job where job_id=$jobid) and _job_db=2";
    my $rows  = $dbh->selectall_arrayref($query);
    if ($rows && (@$rows > 0)) {
        %$data = map { $_->[0], $_->[1] } @$rows;
    }
    return $data;
}

sub set_job_attributes {
    my ($dbh, $jobid, $data) = @_;
    return set_job_tag_data($dbh, $jobid, $data, "JobAttributes");
}

sub set_job_statistics {
    my ($dbh, $jobid, $data) = @_;
    return set_job_tag_data($dbh, $jobid, $data, "JobStatistics");
}

sub set_job_tag_data {
    my ($dbh, $jobid, $data, $table) = @_;
    unless ($data && %$data) {
        return 0;
    }
    my $query = $dbh->prepare(qq(insert into $table (`tag`,`value`,`job`,`_job_db`) values (?,?,(select _id from Job where job_id=$jobid),2) on duplicate key update value=?));
    while ( my ($tag, $val) = each(%$data) ) {
        $query->execute($tag, $val, $val) || return 0;
    }
    return 1
}

my $m5rna_index = "m5rna.clust.index";

sub template_keywords {
    return {
        # versions
        'pipeline_version'   => $Conf::current_pipeline,
        'ach_sequence_ver'   => "7",
        'ach_annotation_ver' => "1",

        # awe clients
        'clientgroups' => "mgrast_dbload,mgrast_single,mgrast_multi",
        'priority'     => 1,
        'docker_image_version' => "latest",

        # urls
        'shock_url'  => $Conf::shock_url,
        'mgrast_api' => $Conf::internal_url,
        'api_key'    => $Conf::api_key,

        # default options
        'prefix_length' => '50',
        'fgs_type'      => '454',
        'aa_pid'        => '90',
        'rna_pid'       => '97',
        'overlap'       => '10',

        # shock data download urls m5nr v1
        'scg_md5_url'         => $Conf::shock_url."/node/524aec48-6c6f-4ad1-8f45-cfd39d1b9060?download",
        'm5nr1_download_url'  => $Conf::shock_url."/node/4406405c-526c-4a63-be22-04b7c2d18434?download",
        'm5nr2_download_url'  => $Conf::shock_url."/node/65d644a8-55a5-439f-a8b5-af1440472d8d?download",
        'm5rna_download_url'  => $Conf::shock_url."/node/1284813a-91d1-42b1-bc72-e74f19e1a0d1?download",
        'm5nr_annotation_url' => $Conf::shock_url."/node/e5dc6081-e289-4445-9617-b53fdc4023a8?download",
        'm5nr_full_db_url'    => $Conf::shock_url."/node/0e275af5-98a3-4857-a47c-0c8c78b5f481?download",
        'm5nr_taxonomy_url'   => $Conf::shock_url."/node/edd8ef09-d746-4736-a6a0-6a83208df7a1?download",
        'm5nr_ontology_url'   => $Conf::shock_url."/node/2a7e0d4d-a581-40ab-a989-53eca51e24a9?download",

        # rna search predata
        'm5rna_clust'       => "m5rna.clust.fasta",
        'm5rna_index'       => $m5rna_index,
        'm5rna_index_burst' => $m5rna_index.".bursttrie_0.dat",
        'm5rna_index_kmer'  => $m5rna_index.".kmer_0.dat",
        'm5rna_index_pos'   => $m5rna_index.".pos_0.dat",
        'm5rna_index_stat'  => $m5rna_index.".stats",
        'm5rna_clust_download_url'       => $Conf::shock_url."/node/c4c76c22-297b-4404-af5c-8cd98e580f2a?download",
        'm5rna_index_burst_download_url' => $Conf::shock_url."/node/1a6768c2-b03a-4bd9-83aa-176266bbc742?download",
        'm5rna_index_kmer_download_url'  => $Conf::shock_url."/node/61cd91d8-c124-4a53-9b65-8cd87f88aa32?download",
        'm5rna_index_pos_download_url'   => $Conf::shock_url."/node/5190f16f-1bbc-44ba-a226-47add7889b0a?download",
        'm5rna_index_stat_download_url'  => $Conf::shock_url."/node/266a5154-7a06-4813-b948-0524155c71ec?download",

        # shock data download urls m5nr v10
        'm5nr1_v10_download_url' => $Conf::shock_url.'/node/a4ba44e1-ea2c-4807-adaf-1bf1346ece34?download',
        'm5nr2_v10_download_url' => $Conf::shock_url.'/node/17a63932-21d3-4fab-ae02-42a9b998e68a?download',
        'm5nr3_v10_download_url' => $Conf::shock_url.'/node/5a95a53e-e6a7-490d-b327-60de298c9056?download',
        'm5nr4_v10_download_url' => $Conf::shock_url.'/node/f9961f5c-f089-49d4-bc33-628b3ac28312?download',
        'm5nr5_v10_download_url' => $Conf::shock_url.'/node/33b7cab0-7d9d-43e6-b0ae-8f35ea63d152?download',
        'm5rna_v10_download_url' => $Conf::shock_url.'/node/2c16497c-762d-4b93-af3c-8aff6f7ccabc?download',
        'm5rna_v10_clust_download_url' => $Conf::shock_url.'/node/715c7ebe-b6bd-472a-a36e-590c0c737d43?download',
        'm5nr_v10_annotation_url' => $Conf::shock_url.'/node/7be4ac73-9037-458a-99df-393ef2c34dfe?download'
    };
}

sub validate_indexes {
    my ($screen_indexes) = @_;
    my @valid_indexes  = ();
    my $bowtie_indexes = bowtie_indexes();
    foreach my $idx (split(/,/, $screen_indexes)) {
        if (exists $bowtie_indexes->{$idx}) {
            push @valid_indexes, $idx;
        }
    }
    if (@valid_indexes == 0) {
        # just use default
        @valid_indexes = ('h_sapiens');
    }
    return join(",", @valid_indexes);
}

sub bowtie_indexes {
    return {
        'a_thaliana'     => {
                                'a_thaliana.1.bt2' => 'fd2589fe-2829-4978-a395-55577c4a37bc',
                                'a_thaliana.2.bt2' => '5510e806-f602-4651-8361-a448131fcb8e',
                                'a_thaliana.3.bt2' => '155d3339-9d72-43fc-925b-04be3101bf51',
                                'a_thaliana.4.bt2' => '27d9e7fb-ff58-4d67-bf94-a4b044c3a979',
                                'a_thaliana.rev.1.bt2' => 'f9ab0db6-265c-4cda-872f-d7673091f3b1',
                                'a_thaliana.rev.2.bt2' => 'b05fe2b1-8af5-4591-8994-7d25388fd911'
                            },
        'b_taurus'       => {
                                'b_taurus.1.bt2' => '1c8f03be-3f82-433f-9499-39b88f01fbaa',
                                'b_taurus.2.bt2' => 'd13be172-6055-4d1e-8523-ae463dccfc7e',
                                'b_taurus.3.bt2' => 'b79e0584-02b7-403e-af60-1344c6f68309',
                                'b_taurus.4.bt2' => '516d5c61-0f41-467c-83b4-673f71dcb9a3',
                                'b_taurus.rev.1.bt2' => 'd30faffa-436b-4626-9cc3-b6aebdf7a919',
                                'b_taurus.rev.2.bt2' => '5b57ddb0-695d-41c8-818f-2eed77c4e7e0'
                            },
        'd_melanogaster' => {
                                'd_melanogaster.1.bt2' => 'b2b58ae0-afbc-4b82-a24d-cd9aabe5aba1',
                                'd_melanogaster.2.bt2' => '0582ada2-b4dd-405d-b053-a1debf381deb',
                                'd_melanogaster.3.bt2' => 'c0f5854d-2b17-4ed7-ad6e-63f49ab6e455',
                                'd_melanogaster.4.bt2' => '987571de-7aa5-427d-a8e5-a10c5ba6871b',
                                'd_melanogaster.rev.1.bt2' => 'e6963ad1-c3e1-4175-a251-ba4502fa6303',
                                'd_melanogaster.rev.2.bt2' => 'acc9b5f9-4a57-461b-be37-039bb2f6ce8f'
                            },
        'e_coli'         => {
                                'e_coli.1.bt2' => '66fe2976-80fd-4d67-a5cd-051018c49c2b',
                                'e_coli.2.bt2' => 'd0eb4784-2f4a-4093-8731-5fe158365036',
                                'e_coli.3.bt2' => '75acfaea-bc42-4f02-a014-cdff9f025e2e',
                                'e_coli.4.bt2' => 'f85b745c-0bea-4bac-9fa4-530411f3bc1c',
                                'e_coli.rev.1.bt2' => '94e7b176-034f-4297-957e-cbcaa7cbc583',
                                'e_coli.rev.2.bt2' => 'd0e023b1-7ada-4d10-beda-9db9a681ed57'
                            },
        'h_sapiens'      => {
                                'h_sapiens.1.bt2' => '12c7a5dc-7859-43cb-a7a0-42a7d2ec3d29',
                                'h_sapiens.2.bt2' => '87eeeac0-b3df-4872-9a71-8f5a984a78f0',
                                'h_sapiens.3.bt2' => 'ea8914ab-7425-401f-9a86-5e10210e10b4',
                                'h_sapiens.4.bt2' => '95da2457-d214-4357-b039-47ef84387ae6',
                                'h_sapiens.rev.1.bt2' => '88a60d6f-8281-4b77-b86e-c8ca8b21b049',
                                'h_sapiens.rev.2.bt2' => 'bd6a2f1d-87fb-42eb-a1ce-fb506b8da65a'
                            },
        'm_musculus'     => {
                                'm_musculus.1.bt2' => '15ff76c8-fab4-41ac-83ec-e41c75577451',
                                'm_musculus.2.bt2' => '8d2e1fb0-fde2-4d23-b0e3-9538d4c3cfd0',
                                'm_musculus.3.bt2' => 'd5b42419-45db-400b-9dad-88b63e4fdcab',
                                'm_musculus.4.bt2' => '6176d3bc-4935-408b-a8aa-e620091915d5',
                                'm_musculus.rev.1.bt2' => 'c2e2e1dc-2e41-40ef-b132-ae985c55b082',
                                'm_musculus.rev.2.bt2' => '18ac35ba-f4e5-474c-9731-cb404d31a793'
                            },
        'r_norvegicus'   => {
                                'r_norvegicus.1.bt2' => 'cefeda69-ac50-416d-baae-8826c5055464',
                                'r_norvegicus.2.bt2' => '9a75b806-09e5-4773-b782-d143c80da95b',
                                'r_norvegicus.3.bt2' => '8a612904-b15f-4b58-9fe3-3b07424e79d5',
                                'r_norvegicus.4.bt2' => 'e93e43a8-bdbb-42b6-a713-aea5c5df4ca1',
                                'r_norvegicus.rev.1.bt2' => '20b18ff9-a189-4ad2-bed7-20547a68caef',
                                'r_norvegicus.rev.2.bt2' => '58ab6851-2c66-47d0-a7fb-925bc6f6a556'
    			            },
        's_scrofa'       => {
                                's_scrofa.1.bt2' => 'fba406ba-451c-4fbc-a5b7-86fd506856f3',
                                's_scrofa.2.bt2' => 'cf9ff454-acda-425d-b8ef-3a5a9b27da5c',
                                's_scrofa.3.bt2' => '00d8262f-7131-497d-a694-85fb1c165dcb',
                                's_scrofa.4.bt2' => '4c011cd7-4bb5-40ba-8a9e-3a7436ec1f51',
                                's_scrofa.rev.1.bt2' => '9cbbc2a4-fbd9-4c8e-9423-82f1e693387a',
                                's_scrofa.rev.2.bt2' => 'a01e41ab-f3e4-439a-a9c6-0bf39ff8e787'
                            },
         'd_rerio'        => {
           'd_rerio.1.bt2' => '08aba193-b244-46a4-b651-0edf1b92920f',
           'd_rerio.2.bt2' => '655414f2-677d-4d22-91c6-31f9a0d950eb',
           'd_rerio.3.bt2' => '9bf4d162-02ae-4a93-9292-d8de56e41fe1',
           'd_rerio.4.bt2' => '151e7d4f-50d2-4298-b597-1d358a2c09fc',
           'd_rerio.rev.1.bt2' => '81777522-e3c2-4e58-8ff7-b96a53b2c2f7',
           'd_rerio.rev.2.bt2' => 'ad50a353-3dc8-48d5-ad1c-340140d9494c'

         },
         'p_maniculatus'    => {
           'p_maniculatus.1.bt2' => "8e07e179-8aeb-4668-b35d-dfc72c446d78",
           'p_maniculatus.2.bt2' => "b238f77d-3d87-4a5c-86e0-ee6ed2ad2ecc",
           'p_maniculatus.3.bt2' => "7be88303-f8c7-4ae7-8527-2b1287787c87",
           'p_maniculatus.4.bt2' => "a224c0be-9a54-4888-b98d-50c5ad9eebbd",
           'p_maniculatus.rev.1.bt2' => "84e5371f-bb7b-44a0-b9a0-82ec37f4fc1e",
           'p_maniculatus.rev.2.bt2' => "266138b5-3ef2-44c0-8bc9-5808b9ddf594"
         }




    };
}

1;
