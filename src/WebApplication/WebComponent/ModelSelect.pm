package WebComponent::ModelSelect;

use strict;
use warnings;
use base qw( WebComponent );

1;

use File::Temp;
use URI::Escape;
use Conf;
use WebComponent::WebGD;
use WebColors;
use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset dataset_is_phylo dataset_is_metabolic get_public_metagenomes );

=pod
=head1 NAME
=head1 DESCRIPTION
=head1 METHODS
=over 4
=item * B<new> ()
Called when the object is initialized. Expands SUPER::new.
=cut

sub new {
    my $self = shift->SUPER::new(@_);

    $self->application->register_component('FilterSelect', 'modelfilterselect');

    return $self;
}

=item * B<output> ()
Returns the html output of the ModelMap component.
=cut
sub output {
    my ($self, $string) = @_;

    return $self->select_content($string);
}

=item select_content ()
Generates the html encoding the model select box.
=cut
sub select_content {
    my ($self, $string) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');
    my $mgrast_genomes = $self->available_metagenomes();

    # Use a hash to alphabetize output
    my $models = {};

    my $labels = [];
    my $values = [];
    my $attributes;
    if (!defined($self->{"_MGRAST select"}) || $self->{"_MGRAST select"} == 0) {
        $attributes = [  {   name => 'Source',
                possible_values => [ ['SEED', 1], ['RAST', 0] ,['Published',1] ],
                values => [] },
            {   name => 'Organism class',
                possible_values => ['Gram positive', 'Gram negative', 'Other'],
                values => [] },
            {   name => 'Genome availability',
                possible_values => [ 'Public', 'Private' ],
                values => [] } ];
    } else {
        $attributes = [  {   name => 'Source',
                possible_values => [ ['MGRAST',1], ['SEED', 0], ['RAST', 0], ['Published',0] ],
                values => [] },
            {   name => 'Organism class',
                possible_values => ['Gram positive', 'Gram negative', 'Other'],
                values => [] },
            {   name => 'Genome availability',
                possible_values => [ 'Public', 'Private' ],
                values => [] } ];
    }

    #Getting username
    my $UserID = "NONE";
    if (defined($self->application->session->user)) {
      $UserID = $self->application->session->user->login;
    }

    #Get model table
    for (my $i=0; $i < $figmodel->number_of_models(); $i++) {
        my $model = $figmodel->get_model($i);
        my $name = "Uknown";
        my $class = "Other";
        my $private = "Public";
        my $source = "Published";
        if ($model->source() =~ m/(SEED)/ || $model->source() =~ m/(MGRAST)/ || $model->source() =~ m/(RAST)/) {
            $source = $1;
        }
        if ($model->source() =~ m/MGRAST/) {
            $private = "forbidden";
            if (defined($mgrast_genomes->{$model->genome()})) {
                if ($mgrast_genomes->{$model->genome()} =~ m/public/) {
                    $name = substr($mgrast_genomes->{$model->genome()},9);
                    $private = "Public";
                } else {
                    $name = substr($mgrast_genomes->{$model->genome()},10);
                    $private = "Private";
                }
            }
        } else {
            $name = $model->name();
            if (defined($model->stats()) && $model->stats()->{Class}->[0] =~ m/Gram/) {
                $class = $model->stats()->{Class}->[0];
            }
            if ($model->public() == 0) {
                if ($model->rights($UserID)) {
                    $private = "Private";
                } else {
                    $private = "forbidden";
                }
            }
        }
        if ($private ne "forbidden") {
            $models->{$model->id()} = [$name,$source,$class,$private];
        }
    }

    foreach (sort{$models->{$a}->[0] cmp $models->{$b}->[0]} keys(%$models)) {
        push @$values, $_;
        push @$labels, $models->{$_}->[0]." ( $_ )";
        push @{$attributes->[0]->{values}}, $models->{$_}->[1];
        push @{$attributes->[1]->{values}}, $models->{$_}->[2];
        push @{$attributes->[2]->{values}}, $models->{$_}->[3];
    }

    # Use a filter_select to select models
    my $filter = $application->component('modelfilterselect');
    $filter->size(14);
    $filter->labels($labels);
    $filter->values($values);
    $filter->attributes($attributes);
    $filter->auto_place_attribute_boxes(0);

    # Format output
    my $compare_string = '<div style="padding-left: 15px; padding-right: 15px; padding-top:10px; text-align: justify;">';
    $compare_string .= "<i>$string</i><br><br>";
    $compare_string .= '<form action="" onsubmit="addModelParam( this.filter_select_'.$filter->{id}.'.value ); return false;" >';
    $compare_string .= '<table><tr><td>'.$filter->output().'</td>';
    my $boxes = $filter->get_attribute_boxes();
    $compare_string .= '<td>'.'<table><tr><td>'.$boxes->{'Organism class'}.'</td><td>'.$boxes->{'Source'}.'</td></tr>';
    $compare_string .= '<tr><td>'.$boxes->{'Genome availability'}.'</td></tr></table>';
    $compare_string .= '</td></tr></table>';
    $compare_string .= "<br><br>";
    $compare_string .= "<input type=\"submit\" value=\"Select Model\">";
    $compare_string .= "</form></div>";

    return $compare_string;
}

sub available_metagenomes {
    my ($self) = @_;

    my $mg_list = {};

    # check for available metagenomes
    my $mgrast = $self->application->data_handle('MGRAST');

    my $org_seen;
    if (ref($mgrast)) {
        my ($public_metagenomes) = &get_public_metagenomes($mgrast);
        foreach my $pmg (@$public_metagenomes) {
            $mg_list->{$pmg->genome_id()} = "public - " . $pmg->genome_name();
            $org_seen->{$pmg->genome_id()}++;
        }

        if ($self->application->session->user) {
            my $mgs = $mgrast->Job->get_jobs_for_user($self->application->session->user, 'view', 1);
            # build hash from all accessible metagenomes
            foreach my $mg_job (@$mgs) {
                next if ($org_seen->{$mg_job->genome_id()});
                $mg_list->{$mg_job->genome_id()} = "private - " . $mg_job->genome_name();
                $org_seen->{$mg_job->genome_id()}++;
            }
        }
    } else {
        # no rast/user, no access to metagenomes
    }

    return $mg_list;
}
