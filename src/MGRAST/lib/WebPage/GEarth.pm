package MGRAST::WebPage::gex2;

use strict;
use warnings;

use POSIX;
use File::Basename;
use MGRAST::Metadata;
use MGRAST::Analysis;

use WebConfig;
use base qw( WebPage );
1;

sub init{
  my ($self) = @_;
  my $cgi = $self->app->cgi;
  $self->application->register_component('Ajax', 'display_ajax');
  
  # access to MetaData module
  my $mddb = MGRAST::Metadata->new();

  $self->data('mddb', $mddb);
  $self->application->register_component('TabView', 'TestTabView');
  $self->application->register_component('Table', 'testtable');
  $self->application->register_component('PieChart', 'test_pie');
  $self->application->register_component('Tree', 'Testtree');
  $self->application->register_component('KEGGMap', 'testmap');
}

sub output{
  my ($self) = @_;
  my $cgi = $self->app->cgi;
  my $html = "";
  my $placemarks = "";
  my $dbh;
  my $exc;
  my $sql;
  my @coords;

  # database handle for metadata
  my $mddb = $self->data('mddb')->_handle();
  print STDERR $mddb."\n";

  my $results = $mddb->Search->get_objects({});
  my $metagenomes = [];
  foreach (@$results){
    if( $_->latitude() ne "" &&  $_->longitude() ne "" && $_->latitude() =~ /\d\.?\d*/ && $_->longitude() =~ /\d\.?\d*/){
      push (@$metagenomes, $_);
      push (@coords, [$_->job(),  $_->latitude(), $_->longitude()]);
    }
  }

  $html .= $self->application->component('display_ajax')->output();
  $html .= <<END;
    <script src="http://earth-api-utility-library.googlecode.com/svn/tags/extensions-0.1.2/dist/extensions.pack.js"> </script>
    <script src="http://www.google.com/jsapi?key=ABQIAAAA4RlUELXDI8mKjFbwFF07yRTh5J3cWfCjA0OnSCGQ4OWWaS1WtRTxPuNWopf3-9qRlt1Ez__h0DU5Zg"></script>

<script type="text/javascript">

var ge = null;
var gex = null;
    
google.load("earth", "1");
    
google.setOnLoadCallback(function() {
  google.earth.createInstance('map3d', function(pluginInstance) {
    ge = pluginInstance;
    ge.getWindow().setVisibility(true);
    ge.getNavigationControl().setVisibility(ge.VISIBILITY_AUTO);

    gex = new GEarthExtensions(pluginInstance);
    gex.util.lookAt([0, 0], { range: 25000000 });

END

  foreach my $c (@coords) {
    my ($job, $lat, $lon) = ($c->[0], $c->[1], $c->[2]);
    print STDERR $job->genome_id(), '\t';
    my $line = 'createPlacemark("'.$job->genome_id.'", "'.$job->genome_name().'", '.$lat.', '.$lon.');';
    $html .= <<END;
    $line
END
  }
  $html .= <<END;
    function createPlacemark(job, name, lat, lon) {
      var placemark = gex.dom.addPointPlacemark([lat, lon], { name: name, style: { icon: { stockIcon: "paddle/red-circle" }}});

      google.earth.addEventListener(placemark, 'click', function(event) {
        event.preventDefault();

        var balloon = ge.createHtmlStringBalloon('');
        balloon.setFeature(event.getTarget());
        balloon.setMinWidth(200);
        balloon.setMinHeight(200);

        html = '<div id="popup_window"></div><img src="./Html/clear.gif" onload="execute_ajax(\\\'display_content\\\', \\\'popup_window\\\', \\\'metagenome_id=METAGENOMEID\\\');"/>';
        re = /METAGENOMEID/;
        html = html.replace(re, job);

        balloon.setContentString(html);

        ge.setBalloon(balloon);
      });
    }
  }, function() {});
});

    </script>
    <div id="sample-ui"></div>
    <div id="map3d" style="width: 100%; height: 600px;"></div>
    <textarea id="code" style="font-family: monospace; width: 500px; height: 200px;">
gex.dom.clearFeatures();

for (var i = 0; i < 1.0; i += 0.1) {
  gex.dom.addPointPlacemark([0, i * 4 - 2], {
    style: {
      icon: {
        stockIcon: 'paddle/wht-blank',
        color: gex.util.blendColors('red', 'green', i)
      }
    }
  });
}
    </textarea><br/>
    <input type="button" onclick="eval(document.getElementById('code').value);" value="Run"/>

END

  return $html;
}

sub display_content {
  my ($self) = @_;
  my $cgi = $self->application->cgi();
  my $metagenome_id = $cgi->param('metagenome_id');
  my $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $metagenome_id });
  my $mgdb = MGRAST::Analysis->new($job);
  unless (ref $mgdb) {
	print STDERR "no databases\n";
	exit;
	}
    $self->data('mgdb', $mgdb);
  my $counts = $mgdb->get_hits_count('SEED:subsystem_tax');

  my $mddb = $self->data('mddb')->_handle();
  my $object_list = $mddb->JobMD->get_objects( { job => $job } );
  my $metagenome_name = "";
  my $project_name = "";
  my $latitude = "";
  my $longitude = "";
  my $habitat = "";
  my $altitude = "";
  my $depth = "";
  my $temperature = "";
  my $humidity = "";
  my $pH = "";
  my $salinity = "";
  my $sampling_date = "";
  my $firstname = "";
  my $lastname = "";
  my $email = "";
  my $organization = "";
  my $organization_url = "";
  foreach my $object (@$object_list) {
    if ($object->tag() eq 'metagenome_name') {
      $metagenome_name = $object->value();
    }
    if ($object->tag() eq 'project_name') {
      $project_name = $object->value();
    }
    if ($object->tag() eq 'latitude') {
      $latitude = $object->value();
    }
    if ($object->tag() eq 'longitude') {
      $longitude = $object->value();
    }
    if ($object->tag() eq 'habitat') {
      $habitat = $object->value();
    }
    if ($object->tag() eq 'altitude') {
      $altitude = $object->value();
    }
    if ($object->tag() eq 'depth') {
      $depth = $object->value();
    }
    if ($object->tag() eq 'temperature') {
      $temperature = $object->value();
    }
    if ($object->tag() eq 'humidity') {
      $humidity = $object->value();
    }
    if ($object->tag() eq 'pH') {
      $pH = $object->value();
    }
    if ($object->tag() eq 'salinity') {
      $salinity = $object->value();
    }
    if ($object->tag() eq 'sampling_date') {
      $sampling_date = $object->value();
    }
    if ($object->tag() eq 'firstname') {
      $firstname = $object->value();
    }
    if ($object->tag() eq 'lastname') {
      $lastname = $object->value();
    }
    if ($object->tag() eq 'email') {
      $email = $object->value();
    }
    if ($object->tag() eq 'organization') {
      $organization = $object->value();
    }
    if ($object->tag() eq 'organization_url') {
      $organization_url = $object->value();
    }

  }

  my $table_component = $self->application->component('testtable');
  $table_component->data([ ['Name',$metagenome_name], ['Project',$project_name], ['Latitude',$latitude], ['Longitude',$longitude], ['Habitat',$habitat], ['Altitude',$altitude], ['Depth',$depth], ['Temperature',$temperature], ['Humidity',$humidity], ['pH',$pH], ['Salinity',$salinity], ['Sampling Date',$sampling_date], ['First Name',$firstname], ['Last Name',$lastname], ['E-mail Address',$email], ['Organization',$organization], ['URL',$organization_url] ]);
  $table_component->columns( [ { 'name' => 'Key' },
                               { 'name' => 'Value' } ] );
  $table_component->items_per_page(17);
  my $table = $table_component->output();

  my $pie = $self->application->component('test_pie');
  $pie->data( [ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 ] );
  my $chart = $pie->output();

  my $tree = $self->application->component('Testtree');
  my $lvl1 = ['Grandfather A','Grandfather B','Grandfather C','Grandfather D'];
  foreach my $l1 (@$lvl1) {
     my $lvl2 = ['Father A','Father B'];
     my $node = $tree->add_node( { 'label' => $l1 } );
     foreach my $l2 (@$lvl2) {
       my $lvl3 = ['Child A', 'Child B', 'Child C'];
       my $child = $node->add_child( { 'label' => $l2 } );
       foreach my $l3 (@$lvl3) {
           $child->add_child( { 'label' => $l3 } );
       }
     }
  }
  my $tre = $tree->output();

  my $kegg_component = $self->application->component('testmap');
  $kegg_component->map_id('00020');
  $kegg_component->highlights([ { id => '2.3.3.1',
                                  tooltip => "Hello World",
                                  link => "http://www.google.de",
                                  target => '_blank' },
                                { id => 'Lysine degradation',
                                  tooltip => "Hello World",
                                  link => "http://www.google.de",
                                  target => '_blank' },
                                { id => 'C00010',
                                  color => [ 0, 255, 0 ] },
                                { id => '00620' },
                                { id => 'R00268',
                                  color => [ [ 255,0,0 ], [ 0,255,0], [ 0,0,255 ] ] } ]);
  my $kegg = $kegg_component->output();

  my $tab_view_component = $self->application->component('TestTabView');
  $tab_view_component->width(300);
  $tab_view_component->height(180);
  $tab_view_component->add_tab('Metadata', $table);
  $tab_view_component->add_tab('Chart', $chart);
  $tab_view_component->add_tab('Tree', $tre);
  $tab_view_component->add_tab('Kegg Map', $kegg);
  my $tabs = $tab_view_component->output();


  return "<b>hey we have content <br> metagenome_id : ".$metagenome_id."<br>counts: ".$counts."<br>".$tabs."<br></b>";
}
