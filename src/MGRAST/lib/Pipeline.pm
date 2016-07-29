package Pipeline;

use strict;
use warnings;
no warnings('once');

use Conf;
use DBI;
use Data::Dumper;

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

sub template_keywords {
    return {
        # versions
        'pipeline_version'   => "3.6",
        'ach_sequence_ver'   => "7",
        'ach_annotation_ver' => "1",

        # awe clients
        'clientgroups' => "mgrast_i2_2xlarge,mgrast_i3_xlarge",
        'priority'     => 1,

        # urls
        'shock_url'  => $Conf::shock_url,
        'mgrast_api' => $Conf::cgi_url,
        'api_key'    => $Conf::api_key,

        # default options
        'prefix_length' => '50',
        'fgs_type'      => '454',
        'aa_pid'        => '90',
        'rna_pid'       => '97',
        'm5rna_clust'   => "md5nr.clust",

        # client certificates in shock
        'cert_shock_url'  => $Conf::shock_url,
        'postgresql_cert' => $Conf::pgsslcert_node,

        # shock data download urls
        'm5nr1_download_url' => "http://shock.metagenomics.anl.gov/node/4406405c-526c-4a63-be22-04b7c2d18434?download",
        'm5nr2_download_url' => "http://shock.metagenomics.anl.gov/node/65d644a8-55a5-439f-a8b5-af1440472d8d?download",
        'm5rna_download_url' => "http://shock.metagenomics.anl.gov/node/1284813a-91d1-42b1-bc72-e74f19e1a0d1?download",
        'm5rna_clust_download_url' => "http://shock.metagenomics.anl.gov/node/c4c76c22-297b-4404-af5c-8cd98e580f2a?download",
        'm5nr_annotation_url' => "http://shock.metagenomics.anl.gov/node/e5dc6081-e289-4445-9617-b53fdc4023a8?download",

        # shock data download urls m5nr v10
        'm5nr1_v10_download_url' => 'http://shock.metagenomics.anl.gov/node/a4ba44e1-ea2c-4807-adaf-1bf1346ece34?download',
        'm5nr2_v10_download_url' => 'http://shock.metagenomics.anl.gov/node/17a63932-21d3-4fab-ae02-42a9b998e68a?download',
        'm5nr3_v10_download_url' => 'http://shock.metagenomics.anl.gov/node/5a95a53e-e6a7-490d-b327-60de298c9056?download',
        'm5nr4_v10_download_url' => 'http://shock.metagenomics.anl.gov/node/f9961f5c-f089-49d4-bc33-628b3ac28312?download',
        'm5nr5_v10_download_url' => 'http://shock.metagenomics.anl.gov/node/33b7cab0-7d9d-43e6-b0ae-8f35ea63d152?download',
        'm5rna_v10_download_url' => 'http://shock.metagenomics.anl.gov/node/2c16497c-762d-4b93-af3c-8aff6f7ccabc?download',
        'm5rna_v10_clust_download_url' => 'http://shock.metagenomics.anl.gov/node/715c7ebe-b6bd-472a-a36e-590c0c737d43?download',
        'm5nr_v10_annotation_url' => 'http://shock.metagenomics.anl.gov/node/7be4ac73-9037-458a-99df-393ef2c34dfe?download',

        # analysis db
        'analysis_dbhost' => $Conf::mgrast_write_dbhost,
        'analysis_dbname' => $Conf::mgrast_db,
        'analysis_dbuser' => $Conf::mgrast_dbuser,
        'analysis_dbpass' => $Conf::mgrast_dbpass
    };
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
                            }
    };
}

1;
