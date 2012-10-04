package WebComponent::RSSFeed;

use strict;
use warnings;

use XML::Simple;

use base qw( WebComponent );

use Conf;

1;

=pod

=head1 NAME

RSSFeed - component to create and display an RSSFeed

=head1 DESCRIPTION

WebComponent to create and display an RSSFeed

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{title} = "";
  $self->{file_name} = "";
  $self->{description} = "";
  $self->{language} = "en-us";
  $self->{pubDate} = "";
  $self->{last_build} = "";
  $self->{items} = [];
  $self->{max_display_items} = 3;
  $self->{show_RSS_link} = 1;
  $self->{xml} = qq~<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>
<rss xmlns:content="http://purl.org/rss/1.0/modules/content/" version="2.0">~;

  $self->application->register_component('Ajax', 'RSSAjax');

  return $self;
}

=item * B<output> ()

Returns the html output of the RSSFeed component.

=cut

sub output {
  my ($self) = @_;

  my $html = "";

  if ($self->show_RSS_link) {
    $html .= "<link rel='alternate' type='application/rss+xml' title='RSS' href='" . $self->url . "' /><a href='" . $self->url . "' target=_blank>RSS feed</a>";
  }

  my $count = 0;
  @{$self->items} = sort { $self->comparable_date($b->{pubDate}) <=> $self->comparable_date($a->{pubDate}) } @{$self->items};
  foreach my $item (@{$self->items}) {
    if ($self->max_display_items && ($count == $self->max_display_items)) {
      my $remain = scalar(@{$self->items}) - $count;
      $html .= "<div><a href='" . $self->url . "' target=_blank>[ $remain more ]</a></div>";
      last;
    }
    $html .= "<div class='news_item'>";
    $html .= "<div class='news_date'>";
    $html .= $self->pretty_date($item->{pubDate});
    $html .= "</div>";
    $html .= "<div class='news_content'>";
    $html .= "<a href='" . $item->{link} . "'>".$item->{title}."</a>";
    $html .= "</div>";
    $html .= "<div class='news_description'>";
    $html .= $item->{description};
    $html .= "</div>";
    $html .= "</div>";
    $count++;
  }

  return $html;
}

sub output_editor {
  my ($self) = @_;

  my $feed_select = "<select name='feed' id='feed_select'>";
  $feed_select .= "<option value='new'>- create new feed -</option>";
  opendir(my $dh, $Conf::temp) || die "can't open feed directory: $!";
  my @feeds = grep { /\.rss$/ && -f "$Conf::temp/$_" } readdir($dh);
  closedir $dh;
  foreach my $feed (@feeds) {
    $feed =~ s/\.rss$//;
    $feed_select .= "<option value='$feed'>$feed</option>";
  }
  $feed_select .= qq~</select><br><input type='button' value='OK' onclick="execute_ajax('output_feed_for_edit', 'feed_span', 'feed='+document.getElementById('feed_select').options[document.getElementById('feed_select').selectedIndex].value, 'loading...', 0, null, 'RSSFeed|~ . $self->{_id} . qq~');">~;

  my $html = $self->application->component('RSSAjax')->output;
  $html .= "<table><tr><td><table><tr><th>Select Feed</th></tr>";
  $html .= "<tr><td>$feed_select</td></tr>";
  $html .= "</table></td><td>";
  $html .= "<span id='feed_span'></span>";
  $html .= "</td></tr></table>";

  return $html;
}

sub output_feed_for_edit {
  my ($self) = @_;

  # get some objects
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $feed = $cgi->param('feed');

  my $items = [];
  my $title = "";
  my $link = "";
  my $description = "";
  my $language = "";
  my $pubDate = "";
  my $lastBuildDate = $self->current_date();

  # check if we get the data to create a new feed
  if ($cgi->param('new')) {
    $feed = $cgi->param('name');
    $self->file_name($feed);
    $self->title($cgi->param('title'));
    $self->url($cgi->param('link'));
    $self->description($cgi->param('description'));
    $self->language($cgi->param('language'));
    $self->pubDate($cgi->param('pubDate'));
    $self->last_build($cgi->param('pubDate'));
    $self->write_feed();
  }

  # check if we want to update the global data on the feed
  if ($cgi->param('update_global')) {
    $feed = $cgi->param('feed');
    $self->file_name($feed);
    $self->load_feed();
    $self->title($cgi->param('title'));
    $self->url($cgi->param('link'));
    $self->description($cgi->param('description'));
    $self->language($cgi->param('language'));
    $self->pubDate($cgi->param('pubDate'));
    $self->last_build($self->current_date);
    $self->write_feed();
  }

  # check if we are editing an existing or creating a new feed
  if ($feed eq 'new') {
    $pubDate = $self->current_date();
  } else {
    $self->file_name($feed);
    $self->load_feed();
    $items = $self->items || [];
    $title = $self->title;
    $link = $self->url;
    $description = $self->description;
    $language = $self->language;
    $pubDate = $self->pubDate;
  }

  # check if we are adding a new item
  if ($cgi->param('add_new')) {
    $self->add_item( { 'title' => $cgi->param('title'),
		       'link' => $cgi->param('link'),
		       'description' => $cgi->param('description'),
		       'category' => $cgi->param('category'),
		       'pubDate' => $cgi->param('pubDate'),
		       'guid' => $cgi->param('guid') } );
    $self->write_feed();
    $items = $self->items();
  }

  if ($cgi->param('remove_item')) {
    $self->delete_item($cgi->param('remove_item'));
    $self->write_feed();
    $items = $self->items();
  }

  # display edit fields for the global properties
  my $content = "<img src='./Html/clear.gif' onload='DatePickerControl.init();'>";
  $content .= "<table><tr><th>global properties</th></tr><tr><td id='feed_global'><form id='feed_form_global'><input type='hidden' name='feed' value='$feed'><input type='hidden' name='update_global' value=1>";
  $content .= "<table>";
  if ($feed eq 'new') {
    $content .= "<tr><th>name</th><td><input type='hidden' name='new' value='1'><input type='text' name='name' size=80></td></tr>";
  }
  $content .= "<tr><th>title</th><td><input type='text' name='title' value='$title' size=80></td></tr>";
  $content .= "<tr><th>link</th><td><input type='text' name='link' value='$link' size=80></td></tr>";
  $content .= "<tr><th>description</th><td><textarea name='description' rows=5 cols=80>$description</textarea></td></tr>";
  $content .= "<tr><th>language</th><td><input type='text' name='language' value='$language'></td></tr>";
  $content .= "<tr><th>pubDate</th><td><input type='text' name='pubDate' readonly=1 value='$pubDate' size=80></td></tr>";
  $content .= "<tr><th>lastBuildDate</th><td><input type='text' name='lastBuildDate' readonly=1 value='$lastBuildDate' size=80></td></tr>";
  $content .= qq~<tr><td colspan=2><input type='button' value='save' onclick="execute_ajax('output_feed_for_edit', 'feed_span', 'feed_form_global', 'saving...', 0, null, 'RSSFeed|~ . $self->{_id} . qq~');"></td></tr>~;
  $content .= "</table></form>";
  $content .= "</td></tr>";

  # display input field for a new item
  $content .= "<tr><th>add new item</th></tr><tr><td id='feed_add_new'><form id='feed_form_add_item'><input type='hidden' name='feed' value='$feed'><input type='hidden' name='add_new' value='1'><table>";
  $content .= "<tr><th>title</th><td><input type='text' name='title' size=80></td></tr>";
  $content .= "<tr><th>link</th><td><input type='text' name='link' size=80></td></tr>";
  $content .= "<tr><th>description</th><td><textarea name='description' rows=5 cols=80></textarea></td></tr>";
  $content .= "<tr><th>category</th><td><input type='text' name='category' size=80></td></tr>";
  $content .= "<tr><th>pubDate</th><td><input type='text' name='pubDate' id='DPC_pubDate' value='" . $self->current_date . "' size=30 readonly=1></td></tr>";
  $content .= "<tr><th>guid</th><td><input type='text' name='guid' size=80></td></tr>";
  $content .= qq~<tr><td colspan=2><input type='button' value='add' onclick="execute_ajax('output_feed_for_edit', 'feed_span', 'feed_form_add_item', 'saving...', 0, null, 'RSSFeed|~ . $self->{_id} . qq~');"></td></tr>~;
  $content .= "</table></form></td></tr>";

  # display the existing items
  if (scalar(@$items)) {
    @{$self->items} = sort { $self->comparable_date($b->{pubDate}) <=> $self->comparable_date($a->{pubDate}) } @{$self->items};
    $content .= "<tr><th>current items</th></tr><tr><td id='feed_existing'><table>";
    foreach my $item (@{$self->items}) {
      $content .= "<tr><th>title</th><td>" . ($item->{title} || "") . "</td></tr>";
      $content .= "<tr><th>link</th><td>" . ($item->{link} || "") . "</td></tr>";
      $content .= "<tr><th>description</th><td>" . ($item->{description} || "") . "</td></tr>";
      $content .= "<tr><th>category</th><td>" . ($item->{category} || "") . "</td></tr>";
      $content .= "<tr><th>pubDate</th><td>" . ($item->{pubDate} || "") . "</td></tr>";
      $content .= "<tr><th>guid</th><td>" . ($item->{guid} || "") . "</td></tr>";
      $content .= qq~<tr><td colspan=2><input type='button' value='delete' onclick="execute_ajax('output_feed_for_edit', 'feed_span', 'feed=$feed&remove_item=~ . $item->{guid} . qq~', 'deleting...', 0, null, 'RSSFeed|~ . $self->{_id} . qq~');"></td></tr>~;
      $content .= "<tr><td colspan=2><hr></td></tr>";
    }
    $content .= "</table></td></tr>";
  }
  
  $content .= "</table></form>";
  
  return $content;
}

sub write_feed {
  my ($self) = @_;
  
  my $xml = $self->xml . qq~
<channel>
<title>~ . $self->title . qq~</title>
<link>~ . $self->url . qq~</link>
<description>~ . $self->description . qq~</description>
<language>~ . $self->language . qq~</language>
<pubDate>~ . $self->pubDate . qq~</pubDate>
<lastBuildDate>~ . $self->last_build . qq~</lastBuildDate>
~;
  
  foreach my $item (@{$self->items}) {
    $xml .= "<item>\n";
    if (exists($item->{title})) {
      $xml .= "<title>".$item->{title}."</title>\n";
    }
    if (exists($item->{link})) {
      $xml .= "<link>".$item->{link}."</link>\n";
    }
    if (exists($item->{description})) {
      $xml .= "<description>".$item->{description}."</description>\n";
    }
    if (exists($item->{category})) {
      $xml .= "<category>".$item->{category}."</category>\n";
    }
    if (exists($item->{pubDate})) {
      if ($item->{pubDate} =~ /^\d+\/\d+\/\d+$/) {
	$item->{pubDate} = $self->reformat_date($item->{pubDate});
      }
      $xml .= "<pubDate>".$item->{pubDate}."</pubDate>\n";
    }
    if (exists($item->{guid})) {
      $xml .= "<guid>".$item->{guid}."</guid>\n";
    }
    if (exists($item->{content})) {
      $xml .= "<content:encoded><![CDATA[".$item->{content}."]]></content:encoded>\n";
    }
    $xml .= "</item>\n";
    
  }
  
  $xml .= qq~</channel>
</rss>\n~;
  
  if (open(FH, ">".$self->file_path)) {
    print FH $xml;
    close FH;
  } else {
    return 0;
  }
}

sub load_feed {
  my ($self) = @_;

  if (-f $self->file_path) {
    my $data = XMLin($self->file_path, forcearray => [ 'item', 'image' ], keyattr => []);
    
    $self->{title} = $data->{channel}->{title};
    $self->{description} = $data->{channel}->{description};
    $self->{language} = $data->{channel}->{language};
    $self->{pubDate} = $data->{channel}->{pubDate};
    $self->{last_build} = $data->{channel}->{lastBuildDate};
    $self->{items} = $data->{channel}->{item};
    
    return $self;
  } else {
    return 0;
  }
}

sub add_item {
  my ($self, $item) = @_;

  push(@{$self->{items}}, $item);

  return $item;
}

sub delete_item {
  my ($self, $uid) = @_;

  my $corrected = [];
  foreach my $item (@{$self->{items}}) {
    unless ($item->{guid} && $item->{guid} eq $uid) {
      push(@$corrected, $item);
    }
  }
  
  $self->{items} = $corrected;

  return $self->{items};
}

sub update_item {
  my ($self, $updated) = @_;

  my $corrected = [];
  foreach my $item (@{$self->{items}}) {
    if ($item->{guid} && $item->{guid} eq $updated->{guid}) {
      push(@$corrected, $updated);
    } else {
      push(@$corrected, $item);
    }
  }
  
  $self->{items} = $corrected;

  return $self->{items};  
}

sub title {
  my ($self, $title) = @_;

  if (defined($title)) {
    $self->{title} = $title;
  }

  return $self->{title};
}

sub file_name { 
  my ($self, $name) = @_;
  
  if (defined($name)) {
    $self->{file_name} = $name;
  }

  return $self->{file_name};
}

sub file_path {
  my ($self) = @_;

  my $path = $Conf::temp . "/" . $self->file_name . ".rss";

  return $path;
}

sub url {
  my ($self) = @_;

  my $url = $Conf::temp_url . "/" . $self->file_name . ".rss";
  
  return $url;
}

sub description {
  my ($self, $description) = @_;

  if (defined($description)) {
    $self->{description} = $description;
  }

  return $self->{description};
}

sub language {
  my ($self, $language) = @_;

  if (defined($language)) {
    $self->{language} = $language;
  }

  return $self->{language};
}

sub pubDate {
  my ($self, $pubDate) = @_;

  if (defined($pubDate)) {
    $self->{pubDate} = $pubDate;
  }

  return $self->{pubDate};
}

sub last_build {
  my ($self, $last_build) = @_;

  if (defined($last_build)) {
    $self->{last_build} = $last_build;
  }

  return $self->{last_build};
}

sub xml {
  my ($self, $xml) = @_;

  if (defined($xml)) {
    $self->{xml} = $xml;
  }

  return $self->{xml};
}

sub items {
  my ($self) = @_;

  return $self->{items};
}

sub pretty_date {
  my ($self, $date) = @_;

  my $name_to_long = { "Jan" => "January",
		      "Feb" => "February", 
		      "Mar" => "March",
		      "Apr" => "April",
		      "May" => "May",
		      "Jun" => "June",
		      "Jul" => "July",
		      "Aug" => "August",
		      "Sep" => "September",
		      "Oct" => "October",
		      "Nov" => "November",
		      "Dec" => "December" };

  my ($day, $mon, $year) = $date =~ /(\d+)\s(\w+)\s(\d+)/;
  if ($day eq "01") {
    $day = "1st";
  } elsif ($day eq "02") {
    $day = "2nd";
  } elsif ($day eq "03") {
    $day = "3rd";
  } else {
    $day = int($day) . "th";
  }
  
  my $pretty_date = $name_to_long->{$mon} . " " . $day . ", " . $year;

  return $pretty_date;
}

sub comparable_date {
  my ($self, $d) = @_;

  my ($day, $mon, $year) = $d =~ /(\d+)\s(\w+)\s(\d+)/;

  my $mon_to_num = { "Jan" => 1,
		     "Feb" => 2, 
		     "Mar" => 3,
		     "Apr" => 4,
		     "May" => 5,
		     "Jun" => 6,
		     "Jul" => 7,
		     "Aug" => 8,
		     "Sep" => 9,
		     "Oct" => 10,
		     "Nov" => 11,
		     "Dec" => 12 };
  
  $d = ($year * 10000) + ($mon_to_num->{$mon} * 100) + int($day);

  return $d;
}

sub max_display_items {
  my ($self, $max) = @_;

  if (defined($max)) {
    $self->{max_display_items} = $max;
  }

  return $self->{max_display_items};
}

sub current_date {
  my ($self) = @_;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  my @month = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
  my @day = qw ( Sun Mon Tue Wed Thu Fri Sat );
  if ($sec < 10) { $sec = "0$sec"; }
  if ($min < 10) { $min = "0$min"; }
  if ($hour < 10) { $hour = "0$hour"; }
  if ($mday < 10) { $mday = "0$mday"; }

  my $date = "$day[$wday], $mday $month[$mon] $year $hour:$min:$sec CST";

  return $date;
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/datepickercontrol.js"];
}

sub require_css {
  return "$Conf::cgi_url/Html/RSSFeed.css";
}

sub show_RSS_link {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_RSS_link} = $show;
  }

  return $self->{show_RSS_link};
}

sub reformat_date {
  my ($self, $date) = @_;

  my ($year, $month, $day) = $date =~ /^(\d+)\/(\d+)\/(\d+)$/;
  my @days = qw ( Sun Mon Tue Wed Thu Fri Sat );
  my @j = (0,3,2,5,0,3,5,1,4,6,2,4);
  my $daynum = ($day + $j[$month - 1] + $year + [$year/4] - [$year/100] + [$year/400]) % 7;
  $day = $days[$daynum];
  my @months = qw( none Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
  $month = $months[$month];
  
  my $formatted_date = "$day, $month $year 12:00:00 CST";
  return $formatted_date;
}
