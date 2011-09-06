package WebComponent::FormWizard::DataStructures;

# Data structures for FormWizard xml

use strict;
use warnings;

use Data::Dumper;
use XML::Simple;

1;

=pod

=head1 NAME

FormWizard Data Structures - Module to create data structures from FormWizard template files 

=head1 DESCRIPTION

Creating data structures for FormWizard from xml template file

=head1 METHODS

=over 4


=item * B<new> (
 template  => xml_template_file,
 noprefix  => true|false ,
 debug     => true|false ,
 database  => database_name,
  )

Called when the object is initialized. 
 

=cut


sub new {
  my ( $class , %params ) = @_ ;
  my $self = %params ? \%params : {} ;
  bless ($self, $class);
  
  # enable unique prefixes by default
  # every question name will be unique within all steps

  unless (defined $params{noprefix}) { $self->noprefix(0); }

  # read config/template file and create FormWizard DataStructures
  if ($self->{template} and -f $self->{template} ) {

    $self->readFormWizardConfig( $self->{template} );
    $self->config2data();
  }
  $self->{using_categories} = 0;

  bless ($self, $class);
  return $self;
}

sub readFormWizardConfig{
  my ($self, $file) = @_;

  if ($file and (-s $file)) {
    my $data = XMLin($file , forcearray => [ 'category', 'question', 'step' , 'unit' ], keyattr => []);
  
    if ($data->{category}) {
      $self->config($data->{category});
      $self->using_categories(1);
    } else {
      $self->config($data->{step});
    }
    $self->{xml} = $data;
    $self->{template} = $file;
  }
  return $file;
}

sub config {
  my ($self, $config) = @_;

  if (defined($config)) {
    $self->{config} = $config;
  }
  return $self->{config};
}

sub using_categories {
  my ($self, $categories) = @_;

  if (defined($categories)) {
    $self->{using_categories} = $categories;
  }
  return $self->{using_categories};
}

sub steps {
  my ($self, $steps) = @_;
  
  if (defined($steps)) {
    $self->{steps} = $steps
  }
  return $self->{steps};
}

sub questions {
  my ($self) = @_;

  my $questions  = {};
  my $categories = $self->categories;
 
  foreach my $group ( values %{ $categories->{groups} } ) {
    foreach my $set ( @$group ) {
      foreach my $q ( @{ $set->{question} } ) {
	$questions->{ $q->{name} } = $q;
      }
    }
  }

  return $questions;
}

sub categories {
  my ($self) = @_;

  # build category list
  unless( ref $self->{categories} and keys %{ $self->{categories} }) {
    my $config   = $self->config();
    my $nr_steps = 0;

    # remember all categories and order of there first occurences
    my $categories = {} ;
    my @order;
    my $exclusive = {};
    foreach my $step (@$config) {
      $nr_steps++;
      if ($step->{category}){
	if ($step->{exclusive}) {
	  $exclusive->{$step->{category}} = 1;
	}
	push @order, $step->{category} unless ( $categories->{$step->{category}} );
	push @{ $categories->{$step->{category}} }, $step;
      }
      else{
	push @order, $step->{data}->{title} unless ( $categories->{$step->{data}->{title}} );
	push @{ $categories->{$step->{data}->{title}} }, $step;
      }
    }
    $self->{categories} = { 
			   order     => \@order ,
			   groups    => $categories,
			   nr_steps  => $nr_steps,
			   exclusive => $exclusive
			  };
  }
  return $self->{categories};
}

sub data {
  my ($self) = @_;
  
  $self->categories();
  unless( ref $self->{data} and @{ $self->{data} }) {
    foreach my $cat_name (@{ $self->{categories}->{order} }) {
      foreach my $step  (@{ $self->{categories}->{groups}->{$cat_name} }) {  
	my $new_step = $self->check_step( $step->{data} );
	foreach my $question (@{$step->{question}}) {
	  $new_step = $self->add_question( $new_step, $question, $cat_name );
	  push @{$self->{data}}, [ $question->{name}, $cat_name, $step->{data}->{title}, $question->{text}, (ref($question->{default}) eq 'HASH') ? '' : $question->{default} ];

	  # build mapping from (automatic) field names to displayed names and categories
	  $self->{name2display}->{ $question->{name} } = { display_text     => $question->{text},
							   display_category => $cat_name,
							   display_title    => $step->{data}->{title}
							 };

	}
      }
    }
  }
  return $self->{data};
}

sub config2data {
  my ($self) = @_;

  return $self->data();
}

sub add_question {
  my ($self, $step, $question ,$category) = @_;

  my $original_name = '';

  # check if we have step and question
  unless (defined($step) && defined($question)) {
    die "called add_question in FormWizard without either a step or a question\n";
  }

  # check the question for all parameters and insert defaults
  unless (defined($question->{text})) {
    $question->{text} = "";
  }

  if (! defined($question->{name})) {
    if ( defined $question->{text} ) {
      my $value = $question->{text};
      $value =~s/[\s\-\/\\\(\)\{\}\[\]\<\>]+/_/g;
      $question->{name} = lc $value;
    }
    else{
      die "called add_question in FormWizard without a parameter name\n";
    }
  }
  elsif (ref $question->{name}) {
    my $data = $question->{name};
    $question->{name} = $data->{content};
    die "called add_question in FormWizard without a parameter name\n" unless ( $question->{name} );
    $question->{migs}      = 1 if ( $data->{migs} );
    $question->{mandatory} = 1 if ( $data->{migs} and $data->{migs} eq "M" );
    $question->{help}      .= "MIGS: ". $data->{definition} if ($data->{definition});
  }
  $original_name = $question->{ name };

  # adding prefix
  unless ($self->noprefix) {
    # add step name 
    my $step_title = $step->{title} || '';
    $step_title =~s/[\s\/\\\(\)\{\}\[\]\<\>]+/-/g;
    $step_title = lc $step_title; 

    $question->{ name } = $step_title ."_". $question->{ name };
    $question->{ name } = $self->prefix   . $question->{ name } if ($self->prefix); 
    
    
  }

  $self->{name2original}->{$question->{name}} = { name     => $original_name,
						  category => $category || 'no category',
						  question => $question,
						};

  # add step name 
  $question->{step_title} = $step->{title};

  # check if the name is already taken
  if (exists($self->{parameters}->{$question->{name}})) {
     die "duplicate name '".$question->{name}."' for parameter in FormWizard\n";
  } else {
    $self->{parameters}->{$question->{name}} = $question->{default};
  }

  unless (defined($question->{type})) {
    $question->{type} = "text";
  }
  
  if ((($question->{type} eq "select") || ($question->{type} eq "radio") || ($question->{type} eq "list")) && (! defined($question->{options}))) {
    die "add_question in FormWizard called with type '".$question->{type}."' and no options\n";
  }

  unless (defined($question->{"default"})) {
    $question->{default} = "";
  }
  unless (defined($question->{mandatory})) {
    $question->{mandatory} = 0;
  }
  push(@{$step->{question}}, $question);

  return $step;
}

sub check_step {
  my ($self, $step) = @_;

  # check if all neccessary data is present / fill in defaults
  unless ($step && (ref($step) eq 'HASH')) {
    die "called add_step in Metadata without a valid step parameter";
  }
  unless (exists($step->{prerequisites})) {
    $step->{prerequisites} = [];
  }
  unless (exists($step->{active})) {
    $step->{active} = 1;
  }
  unless (exists($step->{question})) {
    $step->{question} = [];
  }
  unless (exists($step->{layout})) {
    $step->{layout} = 'double-column';
  }
  unless (exists($step->{title})) {
    $step->{title} = "Step ".(scalar(@{$self->{steps}}) + 1);
  }
  unless (exists($step->{intro})) {
    $step->{intro} = "";
  }
  unless (exists($step->{summary})) {
    $step->{summary} = "";
  }
  return $step;
}



sub prefix {
  my ($self, $prefix) = @_;

  if ($prefix) {
    $self->{prefix} = $prefix;
  }
  return  $self->{prefix} || '';
}

sub noprefix {
  my ($self, $noprefix) = @_;

  if (defined($noprefix)) {
    $self->{noprefix} = $noprefix; 
  }
  return $self->{noprefix};
}

sub name2original {
  my ($self, $name) = @_;

  my ($text, $category, $question) = ('', '', '');

  if (ref $self->{ name2original }->{ $name }) {
    $text     = $self->{ name2original }->{ $name }->{ name };
    $category = $self->{ name2original }->{ $name }->{ category };
    $question = $self->{ name2original }->{ $name }->{ question };
  }
  return ($text, $category, $question);
}

sub name2display {
  my ($self, $name) = @_;

  my ($text, $category, $title) = ('', '', '');

  if (ref $self->{ name2display }->{ $name }) {
    $text     = $self->{ name2display }->{ $name }->{ display_text };
    $category = $self->{ name2display }->{ $name }->{ display_category };
    $title    = $self->{ name2display }->{ $name }->{ display_title };
  }
  return ($text, $category, $title);
}

sub name2display_text {
  my ($self, $name) = @_;
  
  my $text = '';
  if (ref $self->{ name2display }->{ $name }) {
    $text = $self->{ name2display }->{ $name }->{ display_text };
  }
  return $text;
}

sub name2display_category {
  my ($self, $name) = @_;

  my $category = '';
  if (ref $self->{ name2display }->{ $name }) {
    $category = $self->{ name2display }->{ $name }->{ display_category };
  }
  return $category;
}

sub name2display_title {
  my ($self, $name) = @_;

  my $title = '';
  if (ref $self->{ name2display }->{ $name }) {
    $title = $self->{ name2display }->{ $name }->{ display_title };
  }
  return $title;
}

sub debug {
  my ($self, $debug) = @_;
  $self->{ debug } = $debug if (defined $debug and length $debug);
  return $self->{ debug };
}
