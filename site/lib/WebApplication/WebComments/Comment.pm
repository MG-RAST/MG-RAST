package WebComments::Comment;

use strict;
use warnings;
use URI::Escape;

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved


sub validRefObj {
	my ($refstr) = @_;
	return 1;
	if( $refstr =~ m/^fig\|\d+.\d/ ) { return 1; } # fig|83333.1 genomes 
	elsif( $refstr =~ m/^fig\|\d+.\d.str(.\d+)+/) { return 1; } # fig|83333.1.str.1.2.3 strains
	else { return 0; }
}

sub foo {
	my ($self, $hash) = @_;
	unless(@{$self->_master->Comment->get_objects({ ReferenceObject =>
			$hash->{'ReferenceObject'} })}) {
		unless(validRefObj($hash->{'ReferenceObject'})) {
			die "Reference Object '".$hash->{'ReferenceObject'}."' fails to match a valid".
				"reference pattern.";
		}
	}
	$self->SUPER::create(@_);
	# Parse comment Text for '@' symbols
	my $text = uri_unescape($self->Text());
	my $private_hits = 0;
	if($text =~ m/^@/) {	
		$_ = $text;
		my @Matches = /@(\w+)/g;
		foreach my $match (@Matches) {
			my $directed_user = $match; #get user?
			if(defined($directed_user)) { # if the username exists	
				$private_hits++;	
				my $existing_direct = $self->_master->CommentDirectedAt->get_objects({
					Comment => $self, User => $directed_user });
				unless(@{$existing_direct}) {
					$self->_master->CommentDirectedAt->create({ Comment => $self,
						User => $directed_user });
				}
			} 
		}
	}
	if($private_hits) { $self->Private( 'true' ); }
}	
