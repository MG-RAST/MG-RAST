package MGRAST::WebPage::PCA_mgav;

use base qw( WebPage );

1;

use strict;
#use warnings;
use DBI;
use FIG;
use FIG_Config;
use WebConfig;
use WebColors;
use GD;
use WebComponent::WebGD;
use URI::Escape;


use POSIX qw(ceil);

use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset dataset_is_phylo dataset_is_metabolic get_public_metagenomes );

sub init {

  my ($self) = @_;

  $self->title('PCA');
  $self->application->register_component('Table', 'Principal_Components');

  return 1;
}


sub output {

  my ($self) = @_;
  my $cgi = $self->application->cgi;

  my $html = "<h3>Enter comma-separated list of Metagenome Job IDs</h3>";

  #$html .= "<form action='run_pca.cgi' method='post' enctype='multipart/form-data'>\n"; 
  $html .= $self->start_form('jobs_list_form'); 
  $html .= "<p>Job IDs: <input type='txt' name='job_ids' width= 50 /></p>\n";
  $html .= "<p><input type='submit' name='Run_PCA' value='Run PCA'/></p>\n";  
  $html .= "</form>\n";

  if($cgi->param('job_ids')){
      my $result_status = &run_pca_utility;
      if($result_status eq "success"){
	  my $jobs_string = $cgi->param('job_ids');
	  my $dir = $jobs_string;
	  $dir =~s/,//g;
   	  my $link =  $FIG_Config::temp_url."/$dir/pc1_vs_pc2.pdf";
	  $html .= "<a href='$link'>PC1 vs PC2 </a>";
	  $html .= "<br><br>";
	  my $pc_table = $self->application->component('Principal_Components');
	  my $columns = [{ 'name' => 'MG Job ID', 'filter' => 1}, { 'name' => 'PC1', 'sortable'=> 1} , { 'name' => 'PC2','sortable' => 1}];
	  $pc_table->columns ($columns);
	  $pc_table->show_top_browse(1);
	  $pc_table->show_bottom_browse(1);
	  $pc_table->items_per_page(50);
	  $pc_table->width(500);
	  $pc_table->show_select_items_per_page(1);
	  $pc_table->show_export_button({'title' => 'Export Rotational Matrix', 'strip_html' => 1} );

	  my $table_data;

	  my $rotational_matrix_file = $FIG_Config::temp."/$dir/pca_rotational_matrix.txt";
	  open(IN,"$rotational_matrix_file");
	  while($_ = <IN>){
	      chomp($_);
	      #print STDERR "$_\n";
	      my $row;
	      if($_ =~/PC1/){next;}
	      else{
		  $_ =~s/\"//g;
		  my @parts = split("\t",$_);
		  if($parts[0] =~/X(\d+)/){push(@$row,$1);}
		  push(@$row,$parts[1]);
		  push(@$row,$parts[2]);
	      }
	      
	      push(@$table_data,$row);
	  
	  }
	  
	  close(IN);
	  
	  $pc_table->data($table_data);
	  $html .= $pc_table->output();
	  
      }
      else{
	  $html .= "<h4> bad run</h4>";
      }
  }

  return $html;

}

sub run_pca_utility{
    my ($self) = @_;
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $jobs_string = $cgi->param('job_ids');
    my $dir = $jobs_string;
    $dir =~s/,//g;
    my $output_dir = $FIG_Config::temp."/$dir";
    if(! -d $output_dir){ `mkdir $output_dir`;}
    
    $jobs_string =~s/,/ /g;
    `compute_PCA_with_metagenomes_as_variables $output_dir $jobs_string`;
    
    my $return_value;
    if(-s "$output_dir/pc1_vs_pc2.pdf"){$return_value = "success";}
    else{ $return_value =  "failed";}

}
