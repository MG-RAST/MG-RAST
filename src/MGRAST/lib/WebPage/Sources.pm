package MGRAST::WebPage::Sources;

use strict;
use warnings;

use Data::Dumper;
use Babel::lib::Babel;
use base qw( WebPage );

1;

=pod

=head1 NAME

Sources - an instance of WebPage which gives summary information about sources

=head1 DESCRIPTION

Summary page about sources

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Annotation Sources');
  $self->data('show_rna', 1);

  # get data
  my $babel   = new Babel::lib::Babel;
  my $sources = $babel->sources();
  unless ($self->data('show_rna')) {
    %$sources = map { $_, $sources->{$_} } grep { $sources->{$_}{type} ne 'rna' } keys %$sources;
  }
  my %repos = map { $sources->{$_}{source}, 1 } keys %$sources;

  $self->data('babel', $babel);
  $self->data('pids', $babel->count4ids('protein'));
  $self->data('oids', $babel->count4ids('ontology'));
  $self->data('rids', $babel->count4ids('rna'));
  $self->data('pmd5s', $babel->count4md5s('protein'));
  $self->data('rmd5s', $babel->count4md5s('rna'));
  $self->data('funcs', $babel->count4functions());
  $self->data('orgs', $babel->count4organisms());
  $self->data('sources', $sources);

  # register components
  $self->application->register_component('TabView', 'SourceTabs');
  $self->application->register_component('Table', 'SourceStats');
  $self->application->register_component('RollerBlind', 'BuildInfo');
  map { $self->application->register_component('Table', $_ . "_tbl1") } keys %repos;
  map { $self->application->register_component('Table', $_ . "_tbl2") } keys %repos;
  
  return 1;
}

=pod 

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $tab_component = $self->application->component('SourceTabs');
  $tab_component->width(700);
  $tab_component->add_tab('Annotation Source Data', $self->get_build_content());
  $tab_component->add_tab('Table Statistics', $self->get_statistics());
  $tab_component->add_tab('Chart Statistics', $self->get_graphics());

  return "<br><br>" . $tab_component->output();
}

sub get_statistics {
  my ($self) = @_;

  # get data
  my $ids   = $self->data('pids') + $self->data('oids');
  my $md5s  = $self->data('pmd5s');
  my $funcs = $self->data('funcs');
  my $orgs  = $self->data('orgs');
  my $srcs  = $self->data('sources');
  my @data  = ();
  
  if ($self->data('show_rna')) {
    $ids  += $self->data('rids');
    $md5s += $self->data('rmd5s');
  }

  # format data
  foreach (sort {($srcs->{$b}{type} cmp $srcs->{$a}{type}) || ($a cmp $b)} keys %$srcs) {
    my $num_ids = 0;
    if ($srcs->{$_}{protein_ids})  { $num_ids += $srcs->{$_}{protein_ids}; }
    if ($srcs->{$_}{ontology_ids}) { $num_ids += $srcs->{$_}{ontology_ids}; }
    if ($srcs->{$_}{rna_ids})      { $num_ids += $srcs->{$_}{rna_ids}; }

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
			       {'name'=>'Sequences', 'sortable'=>1},
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
  map { $ids   += ($srcs->{$_}{rna_ids} || 0) } keys %$srcs;
  map { $md5s  += ($srcs->{$_}{md5s} || 0) } keys %$srcs;
  map { $funcs += ($srcs->{$_}{functions} || 0) } keys %$srcs;
  map { $orgs  += ($srcs->{$_}{organisms} || 0) } keys %$srcs;

  # get legend
  my @keys   = sort {($srcs->{$b}{type} cmp $srcs->{$a}{type}) || ($a cmp $b)} keys %$srcs;
  my $pad    = "<td>" . ("&nbsp;" x 4) . "</td>";
  my $legend = "<table cellpadding='3'>";
  my $colors = ["#3366cc","#dc3912","#ff9900","#109618","#990099","#0099c6","#dd4477","#66aa00","#b82e2e","#316395","#994499",
		"#22aa99","#aaaa11","#6633cc","#e67300","#8b0707","#651067","#329262","#5574a6","#3b3eac","#b77322","#16d620",
		"#b91383","#f4359e","#9c5935","#a9c413","#2a778d","#668d1c","#bea413","#0c5922","#743411"];
  
  for (my $i = 0; $i < @keys; $i++) {
    my $c_index = $i % scalar(@$colors);
    $legend .= "<tr><td style='width: 15px; background-color: " . $colors->[$c_index] . "';</td>$pad<td>$keys[$i]</td></tr>";
  }
  $legend .= '</table>';

  # get pie charts
  my $data_num  = scalar @keys;
  my $id_rows   = $self->get_pie_data('ids', 'id_data', \@keys);
  my $md5_rows  = $self->get_pie_data('md5s', 'md5_data', \@keys);
  my $func_rows = $self->get_pie_data('functions', 'func_data', \@keys);
  my $org_rows  = $self->get_pie_data('organisms', 'org_data', \@keys);
  my $content   = qq~
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawAll);
  function drawAll() {
    var color_set = GooglePalette($data_num);
    var id_data   = new google.visualization.DataTable();
    var md5_data  = new google.visualization.DataTable();
    var func_data = new google.visualization.DataTable();
    var org_data  = new google.visualization.DataTable();
    id_data.addColumn("string", "Source");
    id_data.addColumn("number", "IDs");
    $id_rows
    drawChart(id_data, "id_pie", color_set);
    md5_data.addColumn("string", "Source");
    md5_data.addColumn("number", "MD5s");
    $md5_rows
    drawChart(md5_data, "md5_pie", color_set);
    func_data.addColumn("string", "Source");
    func_data.addColumn("number", "Funcs");
    $func_rows
    drawChart(func_data, "func_pie", color_set);
    org_data.addColumn("string", "Source");
    org_data.addColumn("number", "Orgs");
    $org_rows
    drawChart(org_data, "org_pie", color_set);
  }
  function drawChart(data, div_id, colors) {
    var chart = new google.visualization.PieChart(document.getElementById(div_id));
    chart.draw(data, {width: 200, height: 200, colors: colors, legend: "none",  chartArea: {left:5,top:0,width:"100%",height:"90%"}});    
  }
</script>
<table cellpadding="5">
<tr>$pad
  <th>IDs (~ . $self->commify($ids) . qq~)</th>$pad
  <th>Sequences (~ . $self->commify($md5s) . qq~)</th>$pad
  <th>Databases</th>
</tr><tr>$pad
  <td><div id='id_pie'></div></td>$pad
  <td><div id='md5_pie'></div></td>$pad
  <td rowspan='3'>$legend</td>
</tr><tr>$pad
  <th>Functions (~ . $self->commify($funcs) . qq~)</th>$pad
  <th>Organisms (~ . $self->commify($orgs) . qq~)</th>$pad
  <td></td>
</tr><tr>$pad
  <td><div id='func_pie'></div></td>$pad
  <td><div id='org_pie'></div></td>$pad
  <td></td>
</tr></table>
~;

  return $content;
}

sub get_pie_data {
  my ($self, $type, $name, $keys) = @_;

  my $srcs = $self->data('sources');
  my @data = ();
  if ($type eq 'ids') {
    @data = map { [ $_, $srcs->{$_}{protein_ids} ? $srcs->{$_}{protein_ids} : ($srcs->{$_}{ontology_ids} ? $srcs->{$_}{ontology_ids} : ($srcs->{$_}{rna_ids} ? $srcs->{$_}{rna_ids} : 0)) ] } @$keys;
  } else {
    @data = map { [ $_, ($srcs->{$_}{$type} ? $srcs->{$_}{$type} : 0) ] } @$keys;
  }
  return join("\n", map { qq($name.addRow(["$_->[0]", $_->[1]]);) } @data);
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

sub require_javascript {
  return ["$Conf::cgi_url/Html/rgbcolor.js", "https://www.google.com/jsapi"];
}
