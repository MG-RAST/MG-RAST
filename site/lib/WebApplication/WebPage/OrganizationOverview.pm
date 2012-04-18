package WebPage::OrganizationOverview;

use base qw( WebPage );

1;

use strict;
use warnings;

use LWP::Simple;

=pod

=head1 NAME

OrganizationOverview - an instance of WebPage which lists all Organizations in a table

=head1 DESCRIPTION

Offers admins the ability to view all organizations

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->application->register_component("Table", "OrganizationTable");
  $self->title('Organization Overview');

  return 1;
}

=item * B<output> ()

Returns the html output of the AccountManagement page.

=cut

sub output {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $org_table = $application->component("OrganizationTable");
  $org_table->columns( [ { name => "Name", sortable => 1, filter => 1 },
			 { name => "Abbreviation", sortable => 1, filter => 1 },
			 { name => "Country", sortable => 1, filter => 1, operator => 'combobox' },
			 { name => "City", sortable => 1, filter => 1 },
			 { name => "url", sortable => 1, filter => 1 },
			 { name => "location", filter => 1 } ] );
  $org_table->show_select_items_per_page(1);
  $org_table->items_per_page(15);
  $org_table->show_top_browse(1);
  $org_table->show_bottom_browse(1);
  $org_table->width('600px');

  my $orgs = $master->Organization->get_objects();
  my $data = [];
  my $lookup_tested = 0;
  my @org_locations;
  foreach my $org (@$orgs) {
    my $name = $org->name || "";
    my $abbr = $org->abbreviation || "";
    my $country = $org->country || "";
    my $city = $org->city || "";
    my $url = $org->url || "";
    my $location = $org->location() || "";
    if ($location && $location ne "0.00, 0.00") {
      push(@org_locations, $location.", ".$org->name);
    }
    
    push(@$data, [$name, $abbr, $country, $city, $url, $location ]);
  }
  $org_table->data($data);
  my $org_locations_string = "<input type='hidden' id='org_locations' value='".join(";", @org_locations)."'>";

  # headline
  my $html = "<h2>Organization Overview</h2>";
  
  # print the table
  $html .= $org_table->output();

  # insert org locations
  $html .= $org_locations_string;
  
  $html .= '<script type="text/javascript" src="http://maps.google.com/maps/api/js?sensor=false"></script>
<script type="text/javascript">
  function initialize() {
     var latlng = new google.maps.LatLng(26.115986, 8.437500);
     var myOptions = {
       zoom: 2,
       center: latlng,
       mapTypeId: google.maps.MapTypeId.HYBRID,
       mapTypeControl: false,
       disableDefaultUI: true
     };
   var map = new google.maps.Map(document.getElementById("map"), myOptions);
   var locs = document.getElementById("org_locations").value.split(";");
   for (i=0; i<locs.length; i++) {
     var loc = locs[i].split(", ");
     var mimg = new google.maps.MarkerImage("./Html/wac_people.png");
     var mark = new google.maps.Marker({ title:loc[2],
                                         icon:mimg,
                                         position: new google.maps.LatLng(loc[0], loc[1]),
                                         map: map });
  }
}

</script>';

  # insert map div
  $html .= qq~<div id="map" style="width: 1000px; height: 600px"></div><img src='./Html/clear.gif' onload='initialize();'>~;

  return $html;
}

sub required_rights {
  return [ [ 'login' ], [ 'edit', 'user', '*' ] ];
}
