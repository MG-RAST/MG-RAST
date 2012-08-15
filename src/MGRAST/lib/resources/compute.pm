package resources::compute;

use strict;
use warnings;

use Conf;

our @ISA = qw( Exporter );
our @EXPORT = qw( status submit delete_job );

my $compute_dir = '/homes/paczian/public/asynch'; # $Conf::compute_dir;

sub status {
  my ($params) = @_;

  my $resource = $params->{resource};
  my $id = $params->{id};

  my $status = "error";
  my $error = "";
  my $time = "";

  if (-f "$compute_dir/$resource/$id.torque_id") {
    my $jobid = `cat $compute_dir/$resource/$id.torque_id`;
    chomp $jobid;
    my $error_file = $jobid.".mcs.anl.gov.OU";
    my ($qtime, $qstatus) = `qstat | grep $jobid` =~ /^.+\s+.+\s+.+\s+(.+)\s+(.+)\s+.+$/;
    if ($qstatus) {
      if ($qstatus eq 'R') {
	$status = "running";
	$time = $qtime;
      } else {
	$status = "waiting";
      }
    } elsif (-f "$compute_dir/$resource/$error_file") {
      $status = "error";
      $error = `cat $compute_dir/$resource/$error_file`;
    } else {
      $status = "complete";
    }
  } else {
    $error = "job does not exist";
  }

  return { status => $status,
	   error => $error,
	   time => $time };
}

sub submit {
  my ($params) = @_;

  my $resource = $params->{resource};
  my $id = $params->{id};
  my $script = $params->{script};

  if ($resource && $id && $script) {
    unless (-d "$compute_dir/$resource") {
      mkdir "$compute_dir/$resource";
      `chmod 777 '$compute_dir/$resource'`;
    }
    
    unless (-f "$compute_dir/$resource/$id.torque_id") {
      if (open(FH, ">$compute_dir/$resource/$id.torque_id")) {
	source();
	my $stuff = `$script`;
	print STDERR $stuff."\n".$script."\n";
	my $jnum = `echo $script | /usr/local/bin/qsub -q fast -j oe -N $resource.$id -l walltime=60:00:00 -m n -o '$compute_dir/$resource'`;
	$jnum =~ s/^(.*)\.mcs\.anl\.gov/$1/;
	print FH $jnum;
	close FH;
      } else {
	die "could not open compute directory $compute_dir/$resource: $@";
      }
    }

    return &status($params);
  } else {
    die "invalid parameters";
  }
}

sub delete_job {
  my ($params) = @_;

  my $resource = $params->{resource};
  my $id = $params->{id};

  if ($resource && $id) {
    if (-f "$compute_dir/$resource/$id.torque_id") {
      my $jobid = `cat $compute_dir/$resource/$id.torque_id`;
      `qdel $jobid`;
      `rm -f $compute_dir/$resource/$id.torque_id`;
      if (-f "$compute_dir/$resource/$jobid") {
	`rm -f $compute_dir/$resource/$jobid`;
      }
      return "job deleted";
    } else {
      return "job does not exist";
    }
  } else {
    die "invalid parameters";
  }
}


sub source {
  $ENV{PATH} = "/mcs/bio/mg-rast/prod/tools:/mcs/bio/mg-rast/prod/pipeline/bin:/mcs/bio/mg-rast/prod/pipeline/stages:/mcs/bio/awe/server/src/sbin:/soft/packages/biotools/bin:/soft/packages/FragGeneScan/1.15/bin:/soft/packages/R/2.11.1/bin:/soft/packages/perl/5.12.1/bin:/soft/packages/python/2.6/bin:/soft/packages/PyroNoise2/bin:/soft/packages/uclust/1.1.579q.64bit:/soft/packages/microbiomeutil/2010-04-29/ChimeraSlayer:/soft/packages/Denoiser/0.851/bin:/soft/packages/Qiime/1.4.0/bin:/soft/packages/circos/0.52.1/bin:/soft/packages/ompp/0.7.1/bin:/soft/packages/454software/2.3/bin:/soft/packages/jellyfish/1.1.4/bin:/soft/packages/cutadapt/1.0/bin:/soft/packages/coreutils/8.13/alias:/soft/packages/jre/1.6.0_21/bin:/usr/kerberos/bin:/usr/local/bin:/bin:/usr/bin";
  $ENV{PYTHONPATH} = "/soft/packages/Denoiser/0.851";
  $ENV{PERL5LIB} = "/mcs/bio/mg-rast/prod/pipeline/lib:/mcs/bio/mg-rast/prod/pipeline/conf";
  $ENV{QIIME_CONFIG_FP} = "/soft/packages/Qiime/1.4.0/.qiime_config";
  $ENV{RDP_JAR_PATH} = "/soft/packages/rdp_classifier/2.0.1/rdp_classifier-2.0.jar";
  $ENV{JAVA_HOME} = "/soft/packages/jre/1.6.0_21";
  $ENV{BLASTMAT} = "/soft/packages/blast/2.2.22";
}

1;
