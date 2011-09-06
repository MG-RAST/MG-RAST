package Babel::WebPage::ViewSources;

use strict;
use warnings;

use base qw( WebPage );

use Babel::lib::Babel;
use Global_Config;
use Data::Dumper;

1;

sub init {
  my $self = shift;
  $self->title("M5NR - Sources");

  # get babel connection
  my $babel   = new Babel::lib::Babel;
  my $sources = $babel->sources();
  my %sub_src = map { $_, $sources->{$_} } grep { $sources->{$_}{type} ne 'rna' } keys %$sources;
  my %repos   = map { $sub_src{$_}{source}, 1 } keys %sub_src;

  # get babel data
  $self->data('babel', $babel);
  $self->data('pids', $babel->count4pids());
  $self->data('oids', $babel->count4oids());
  $self->data('md5s', $babel->count4md5s());
  $self->data('funcs', $babel->count4functions());
  $self->data('orgs', $babel->count4organisms());
  $self->data('sources', \%sub_src);

  # register components
  $self->application->register_component('TabView', 'SourceTabs');
  $self->application->register_component('Table', 'SourceStats');
  $self->application->register_component('PieChart', 'IDPie');
  $self->application->register_component('PieChart', 'MD5Pie');
  $self->application->register_component('PieChart', 'FuncPie');
  $self->application->register_component('PieChart', 'OrgPie');
  $self->application->register_component('RollerBlind', 'BuildInfo');
  map { $self->application->register_component('Table', $_ . "_tbl1") } keys %repos;
  map { $self->application->register_component('Table', $_ . "_tbl2") } keys %repos;
}

sub output {
  my ($self) = @_;

  my $content = "<h2>Source Information for the M5NR</h2><br>";
  my $tab_component = $self->application->component('SourceTabs');
  $tab_component->width(700);
  $tab_component->add_tab('Annotation Source Data', $self->get_build_content());
  $tab_component->add_tab('Table Statistics', $self->get_statistics());
  $tab_component->add_tab('Chart Statistics', $self->get_graphics());

  return $content . $tab_component->output();
}

sub get_statistics {
  my ($self) = @_;

  # get data
  my $ids   = $self->data('pids') + $self->data('oids');
  my $md5s  = $self->data('md5s');
  my $funcs = $self->data('funcs');
  my $orgs  = $self->data('orgs');
  my $srcs  = $self->data('sources');
  my @data  = ();

  # format data
  foreach (sort {($srcs->{$b}{type} cmp $srcs->{$a}{type}) || ($a cmp $b)} keys %$srcs) {
    my $num_ids = $srcs->{$_}{protein_ids} ? $srcs->{$_}{protein_ids} : ($srcs->{$_}{ontology_ids} ? $srcs->{$_}{ontology_ids} : 0);
    push @data, [ $_,
		  qq(<a href="$srcs->{$_}{url}">$srcs->{$_}{source}</a>),
		  $srcs->{$_}{type},
		  $self->commify($num_ids),
		  &get_percent($ids, $num_ids),
		  $self->commify($srcs->{$_}{md5s} ? $srcs->{$_}{md5s} : 0),
		  &get_percent($md5s, $srcs->{$_}{md5s}),
		  $self->commify($srcs->{$_}{functions} ? $srcs->{$_}{functions} : 0),
		  &get_percent($funcs, $srcs->{$_}{functions}),
		  $self->commify($srcs->{$_}{organisms} ? $srcs->{$_}{organisms} : 0),
		  &get_percent($orgs, $srcs->{$_}{organisms}) ];
  }

  # add to table
  my $table_component = $self->application->component('SourceStats');
  $table_component->data( \@data );
  $table_component->columns( [ {'name'=>'Database', 'filter'=>1, 'sortable'=>1},
			       {'name'=>'Source', 'filter'=>1, 'sortable'=>1},
			       {'name'=>'Type', 'sortable'=>1},
			       {'name'=>'Total IDs', 'sortable'=>1},
			       {'name'=>"\% IDs<br>(" . $self->commify($ids) . ")", 'sortable'=>1},
			       {'name'=>'Unique Sequences', 'sortable'=>1},
			       {'name'=>"\% Sequences<br>(" . $self->commify($md5s) . ")", 'sortable'=>1},
			       {'name'=>'Functions', 'sortable'=>1},
			       {'name'=>"\% Functions<br>(" . $self->commify($funcs) . ")", 'sortable'=>1},
			       {'name'=>'Organisms', 'sortable'=>1},
			       {'name'=>"\% Organisms<br>(" . $self->commify($orgs) . ")", 'sortable'=>1}
			      ] );
  $table_component->items_per_page(25);
  $table_component->show_bottom_browse(1);
  $table_component->show_select_items_per_page(1);

  return $table_component->output();
}

sub get_graphics {
  my ($self) = @_;

  # get data
  my ($ids, $md5s, $funcs, $orgs) = (0, 0, 0, 0);
  my $srcs = $self->data('sources');
  map { $ids   += ($srcs->{$_}{protein_ids} || 0) } keys %$srcs;
  map { $ids   += ($srcs->{$_}{ontology_ids} || 0) } keys %$srcs;
  map { $md5s  += ($srcs->{$_}{md5s} || 0) } keys %$srcs;
  map { $funcs += ($srcs->{$_}{functions} || 0) } keys %$srcs;
  map { $orgs  += ($srcs->{$_}{organisms} || 0) } keys %$srcs;

  # get legend
  my @keys   = sort {($srcs->{$b}{type} cmp $srcs->{$a}{type}) || ($a cmp $b)} keys %$srcs;
  my $pad    = "<td>" . ("&nbsp;" x 4) . "</td>";
  my $legend = "<table cellpadding='3'>";

  for (my $i = 0; $i < @keys; $i++) {
    my $color = WebColors::get_palette('excel')->[$i] || [0,0,0];
    $legend .= "<tr><td style='width: 15px; background-color: rgb(" . join(',',@$color) . ")';</td>$pad<td>$keys[$i]</td></tr>";
  }
  $legend .= '</table>';

  # get pie charts
  my $id_pie   = $self->get_pie_chart('ids', 'IDPie', \@keys);
  my $md5_pie  = $self->get_pie_chart('md5s', 'MD5Pie', \@keys);
  my $func_pie = $self->get_pie_chart('functions', 'FuncPie', \@keys);
  my $org_pie  = $self->get_pie_chart('organisms', 'OrgPie', \@keys);
  my $content  = qq~
<table cellpadding="5">
<tr>$pad
  <th>IDs (~ . $self->commify($ids) . qq~)</th>$pad
  <th>Unique Sequences (~ . $self->commify($md5s) . qq~)</th>$pad
  <th>Databases</th>
</tr><tr>$pad
  <td>$id_pie</td>$pad
  <td>$md5_pie</td>$pad
  <td rowspan='3'>$legend</td>
</tr><tr>$pad
  <th>Functions (~ . $self->commify($funcs) . qq~)</th>$pad
  <th>Organisms (~ . $self->commify($orgs) . qq~)</th>$pad
  <td></td>
</tr><tr>$pad
  <td>$func_pie</td>$pad
  <td>$org_pie</td>$pad
  <td></td>
</tr></table>
~;

  return $content;
}

sub get_pie_chart {
  my ($self, $type, $pie, $keys) = @_;

  # get data
  my $srcs = $self->data('sources');
  my @data = ();
  if ($type eq 'ids') {
    @data = map { {'title' => $_,
		   'data'  => $srcs->{$_}{protein_ids} ? $srcs->{$_}{protein_ids} : ($srcs->{$_}{ontology_ids} ? $srcs->{$_}{ontology_ids} : 0)} } @$keys;
  }
  else {
    @data = map { {'title' => $_, 'data' => ($srcs->{$_}{$type} ? $srcs->{$_}{$type} : 0)} } @$keys;
  }

  # add to pie chart
  my $pie_component = $self->application->component($pie);
  $pie_component->data( \@data );
  $pie_component->size(200);
  $pie_component->show_tooltip(1);

  return $pie_component->output();
}

sub get_build_content {
  my ($self) = @_;

  my $repo_down = {};
  my $repo_srcs = {};
  foreach ( sort keys %{$self->data('sources')} ) {
    my $data = $self->data('sources')->{$_};
    my $src  = $data->{source};
    if ($data->{download_path} && (@{$data->{download_path}} > 0)) {
      $repo_down->{$src} = [$data->{download_date}, $data->{url}, $data->{title}, $self->get_file_tbl("${src}_tbl1", $data->{download_path}, $data->{download_file})];
    }
    push @{ $repo_srcs->{$src} }, [$_, $data->{description}, $data->{type}, ($data->{version} || '')];
  }

  my $roll_component = $self->application->component('BuildInfo');
  foreach ( sort keys %$repo_down ) {
    my $content = "<p>The following annotation databases have been obtained from <a href='" . $repo_down->{$_}[1] .
                  "'>$_</a></p><p>" . $self->get_src_tbl("${_}_tbl2", $repo_srcs->{$_}) . "</p>" .
		  "<p>The following files from <a href='" . $repo_down->{$_}[1] .
		  "'>$_</a> have been downloaded and used to build the MD5-NR:</p><p>" . $repo_down->{$_}[3] . "</p>";
    $roll_component->add_blind({'title' => "$_: " . $repo_down->{$_}[2], 'info' => "Last Update: " . $repo_down->{$_}[0], 'content' => $content});
  }
  return $roll_component->output();
}

sub get_file_tbl {
  my ($self, $tbl, $paths, $files) = @_;

  my @data;
  for (my $i=0; $i<@$paths; $i++) {
    push @data, [ $paths->[$i], $files->[$i] ];
  }

  my $tbl_component = $self->application->component($tbl);
  $tbl_component->data( \@data );
  $tbl_component->columns( ['Location', 'Files'] );
  return $tbl_component->output();
}

sub get_src_tbl {
  my ($self, $tbl, $data) = @_;

  my $tbl_component = $self->application->component($tbl);
  $tbl_component->data( $data );
  $tbl_component->columns( ['Database', 'Description', 'Type', 'Version'] );
  return $tbl_component->output();
}

sub get_percent {
  my ($total, $val) = @_;

  if ((! $val) || (! $total)) { return 0; }
  my $num = ($val / $total) * 100;
  return sprintf("%.3f", $num);
}

sub commify {
  my ($self, $num) = @_;

  my $text = reverse $num;
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
}
