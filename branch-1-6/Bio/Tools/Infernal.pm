# $Id$
#
# BioPerl module for Bio::Tools::Infernal
#
# Please direct questions and support issues to <bioperl-l@bioperl.org> 
#
# Cared for by Chris Fields <cjfields-at-uiuc-dot-edu>
#
# Copyright Chris Fields
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Tools::Infernal - A parser for Infernal output

=head1 SYNOPSIS

  use Bio::Tools::Infernal;
  my $parser = Bio::Tools::Infernal->new(-file => $rna_output,
                                        -motiftag => 'misc_binding'
                                        -desctag => 'Lysine riboswitch',
                                        -cm    => 'RF00168',
                                        -rfam  =>  'RF00168',
                                        -minscore => 20);
  #parse the results, get a Bio::SeqFeature::FeaturePair
  while( my $motif = $parser->next_prediction) {
    # do something here
  }

=head1 DESCRIPTION

This is a highly experimental parser for Infernal output from the cmsearch
program.  At some point it is anticipated that this will morph into a proper
SearchIO parser, along with the related RNAMotif and ERPIN tools.

The Infernal suite of programs are used for generating RNA CM (covariance
models) and searching sequences using CMs to locate potentially similar
structures.  The program is under active development; it is anticiapted that
this will support the latest version available.

This parser has been tested and is capable of parsing Infernal 0.7 and 0.71
output.  However, future Infernal versions may break parsing as the output is
constantly evolving, so keep an eye on this space for additional notes.

Currently data is parsed into a Bio::SeqFeature::FeaturePair object, consisting
of a query (the covariance model) and the hit (sequence searched).  

Model data is accessible via the following:

  Data            SeqFeature::FeaturePair         Note
  --------------------------------------------------------------------------
  primary tag     $sf->primary_tag                Rfam ID (if passed to new())
  start           $sf->start                      Based on CM length
  end             $sf->end                        Based on CM length
  score           $sf->score                      Bit score
  strand          $sf->strand                     0 (CM does not have a strand)
  seqid           $sf->seq_id                     Rfam ID (if passed to new())
  display name    $sf->feature1->display_name     CM name (if passed to new())
  source          $sf->feature1->source tag      'Infernal' followed by version

Hit data is accessible via the following:

  Data            SeqFeature::FeaturePair         Note
  ------------------------------------------------------------------
  start           $sf->hstart
  end             $sf->hend
  score(bits)     $sf->hscore
  strand          $sf->hstrand
  seqid           $sf->hseqid
  Primary Tag     $sf->hprimary_tag
  Source Tag      $sf->hsource_tag

Added FeaturePair tags are : 

   secstructure - entire description line (in case the regex used for
                  sequence ID doesn't adequately catch the name
   model        - name of the descriptor file (may include path to file)
   midline      - contains structural information from the descriptor
                  used as a query
   hit          - sequence of motif, separated by spaces according to
                  matches to the structure in the descriptor (in
                  SecStructure).
   seqname      - raw sequence name (for downstream parsing if needed)

An additional parameter ('minscore') is added due to the huge number
of spurious hits generated by cmsearch.  This screens data, only building
and returning objects when a minimal bitscore is present.  

See t/rnamotif.t for example usage.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Support 

Please direct usage questions or support issues to the mailing list:

I<bioperl-l@bioperl.org>

rather than to the module maintainer directly. Many experienced and 
reponsive experts will be able look at the problem and quickly 
address it. Please include a thorough description of the problem 
with code and data examples if at all possible.

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via the
web:

  http://bugzilla.open-bio.org/

=head1 AUTHOR - Chris Fields

Email cjfields-at-uiuc-dot-edu

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::Tools::Infernal;
use strict;

use Bio::SeqFeature::Generic;
use Bio::SeqFeature::FeaturePair;
use Data::Dumper;
use base qw(Bio::Tools::AnalysisResult);

our($MotifTag,$SrcTag,$DescTag) = qw(misc_binding Infernal infernal);

our $MINSCORE = 0;
our $DEFAULT_VERSION = '0.71';

=head2 new

 Title   : new
 Usage   : my $obj = Bio::Tools::Infernal->new();
 Function: Builds a new Bio::Tools::Infernal object 
 Returns : an instance of Bio::Tools::Infernal
 Args    : -fh/-file  - for input filehandle/filename
           -motiftag  - primary tag used in gene features (default 'misc_binding')
           -desctag   - tag used for display_name name (default 'infernal')
           -srctag    - source tag used in all features (default 'Infernal')
           -rfam      - Rfam id number
           -cm        - covariance model used in analysis (may be same as rfam #)
           -minscore  - minimum score (simple screener, since Infernal generates
                        a ton of spurious hits)
           -version   - Infernal program version

=cut

# yes, this is actually _initialize, but the args are passed to
# the constructor.
# see Bio::Tools::AnalysisResult for further details

sub _initialize {
  my($self,@args) = @_;
  $self->warn('Use of this module is deprecated.  Use Bio::SearchIO::infernal instead');  
  $self->SUPER::_initialize(@args);
  my ($motiftag,$desctag,$srctag,$rfam,$cm,$ms,$ver) =
        $self->SUPER::_rearrange([qw(MOTIFTAG
                                    DESCTAG
                                    SRCTAG
                                    RFAM
                                    CM
                                    MINSCORE
                                    VERSION
                                 )],@args);
  $self->motif_tag(defined $motiftag ? $motiftag : $MotifTag);
  $self->source_tag(defined $srctag ? $srctag : $SrcTag);
  $self->desc_tag(defined $desctag ? $desctag : $DescTag);
  $cm        && $self->covariance_model($cm);
  $rfam      && $self->rfam($rfam);
  $self->program_version(defined $ver ? $ver : $DEFAULT_VERSION);
  $self->minscore(defined $ms ? $ms : $MINSCORE);
}

=head2 motif_tag

 Title   : motif_tag
 Usage   : $obj->motif_tag($newval)
 Function: Get/Set the value used for 'motif_tag', which is used for setting the
           primary_tag.
           Default is 'misc_binding' as set by the global $MotifTag.
           'misc_binding' is used here because a conserved RNA motif is capable
           of binding proteins (regulatory proteins), antisense RNA (siRNA),
           small molecules (riboswitches), or nothing at all (tRNA,
           terminators, etc.).  It is recommended that this be changed to other
           tags ('misc_RNA', 'protein_binding', 'tRNA', etc.) where appropriate.
           For more information, see:
           http://www.ncbi.nlm.nih.gov/collab/FT/index.html
 Returns : value of motif_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

=cut

sub motif_tag{
    my $self = shift;

    return $self->{'motif_tag'} = shift if @_;
    return $self->{'motif_tag'};
}

=head2 source_tag

 Title   : source_tag
 Usage   : $obj->source_tag($newval)
 Function: Get/Set the value used for the 'source_tag'.
           Default is 'Infernal' as set by the global $SrcTag
 Returns : value of source_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub source_tag{
    my $self = shift;

    return $self->{'source_tag'} = shift if @_;
    return $self->{'source_tag'};
}

=head2 desc_tag

 Title   : desc_tag
 Usage   : $obj->desc_tag($newval)
 Function: Get/Set the value used for the query motif.  This will be placed in
           the tag '-display_name'.  Default is 'infernal' as set by the global
           $DescTag.  Use this to manually set the descriptor (motif searched for).
           Since there is no way for this module to tell what the motif is from the
           name of the descriptor file or the Infernal output, this should
           be set every time an Infernal object is instantiated for clarity
 Returns : value of exon_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

=cut

sub desc_tag{
    my $self = shift;

    return $self->{'desc_tag'} = shift if @_;
    return $self->{'desc_tag'};
}

=head2 covariance_model

 Title   : covariance_model
 Usage   : $obj->covariance_model($newval)
 Function: Get/Set the value used for the covariance model used in the analysis.
 Returns : value of exon_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

=cut

sub covariance_model{
    my $self = shift;

    return $self->{'_cmodel'} = shift if @_;
    return $self->{'_cmodel'};
}

=head2 rfam

 Title   : rfam
 Usage   : $obj->rfam($newval)
 Function: Get/Set the Rfam accession number
 Returns : value of exon_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

=cut

sub rfam {
    my $self = shift;

    return $self->{'_rfam'} = shift if @_;
    return $self->{'_rfam'};
}

=head2 minscore

 Title   : minscore
 Usage   : $obj->minscore($newval)
 Function: Get/Set the minimum score threshold for generating SeqFeatures
 Returns : value of exon_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

=cut

sub minscore {
    my $self = shift;

    return $self->{'_minscore'} = shift if @_;
    return $self->{'_minscore'};
}

=head2 program_version

 Title   : program_version
 Usage   : $obj->program_version($newval)
 Function: Get/Set the Infernal program version
 Returns : value of exon_tag (a scalar)
 Args    : on set, new value (a scalar or undef, optional)
           Note: this is set to $DEFAULT_VERSION by, um, default

=cut

sub program_version {
    my $self = shift;

    return $self->{'_program_version'} = shift if @_;
    return $self->{'_program_version'};
}

=head2 analysis_method

 Usage     : $obj->analysis_method();
 Purpose   : Inherited method. Overridden to ensure that the name matches
             /Infernal/i.
 Returns   : String
 Argument  : n/a

=cut

sub analysis_method { 
    my ($self, $method) = @_;  
    if($method && ($method !~ /Infernal/i)) {
    $self->throw("method $method not supported in " . ref($self));
    }
    return $self->SUPER::analysis_method($method);
}

=head2 next_feature

 Title   : next_feature
 Usage   : while($gene = $obj->next_feature()) {
                  # do something
           }
 Function: Returns the next gene structure prediction of the RNAMotif result
           file. Call this method repeatedly until FALSE is returned.
           The returned object is actually a SeqFeatureI implementing object.
           This method is required for classes implementing the
           SeqAnalysisParserI interface, and is merely an alias for 
           next_prediction() at present.
 Returns : A Bio::Tools::Prediction::Gene object.
 Args    : None (at present)

=cut

sub next_feature {
    my ($self,@args) = @_;
    # even though next_prediction doesn't expect any args (and this method
    # does neither), we pass on args in order to be prepared if this changes
    # ever
    return $self->next_prediction(@args);
}

=head2 next_prediction

 Title   : next_prediction
 Usage   : while($gene = $obj->next_prediction()) {
                  # do something
           }
 Function: Returns the next gene structure prediction of the RNAMotif result
           file. Call this method repeatedly until FALSE is returned.
 Returns : A Bio::SeqFeature::Generic object
 Args    : None (at present)

=cut

sub next_prediction {
    my ($self) = @_;
    
    my ($start, $end, $strand, $score);
    
    my %hsp_key = ('0' => 'structure',
                   '1' => 'model',
                   '2' => 'midline',
                   '3' => 'hit');
    my $line;
    PARSER:
    while($line = $self->_readline) {
        next if $line =~ m{^\s+$};
        if ($line =~ m{^sequence:\s+(\S+)} ){
            $self->_current_hit($1);
            next PARSER;
        } elsif ($line =~ m{^hit\s+\d+\s+:\s+(\d+)\s+(\d+)\s+(\d+\.\d+)\s+bits}xms) {
            $strand = 1;
            ($start, $end, $score) = ($1, $2, $3);
            if ($start > $end) {
                ($start, $end) = ($end, $start);
                $strand = -1;
            }
            #$self->debug(sprintf("Hit: %-30s\n\tStrand:%-4d Start:%-6d End:%-6d Score:%-10s\n",
            #       $self->_current_hit, $strand, $start, $end, $score));
        } elsif ($line =~ m{^(\s+)[<>\{\}\(\)\[\]:_,-\.]+}xms) { # start of HSP
            $self->_pushback($line); # set up for loop
            # what is length of the gap to the structure data?
            my $offset = length($1);
            my ($ct, $strln) = 0;
            my $hsp;
            HSP:
            while ($line = $self->_readline) {
                next if $line =~ m{^\s*$}; # toss empty lines
                chomp $line;
                # exit loop if at end of file or upon next hit/HSP
                if (!defined($line) || $line =~ m{^(sequence|hit)}) {
                    $self->_pushback($line);
                    last HSP;
                }
                # iterate to keep track of each line (4 lines per hsp block)
                my $iterator = $ct%4;
                # strlen set only with structure lines (proper length)
                $strln = length($line) if $iterator == 0;
                # only grab the data needed (hit start and stop in hit line above;
                # query start, end are from the actual query length (entire hit is
                # mapped to CM data, so all CM data is represented
                
                # yes this is kinda clumsy, but I'll probably morph this into
                # a proper SearchIO module soon.  For now this works...
                my $data = substr($line, $offset, $strln-$offset);
                $hsp->{ $hsp_key{$iterator} } .= $data;
                $ct++;
            }
            if ($self->minscore < $score) {
                my ($name, $program, $rfam, $cm, $dt, $st, $mt) =
                  ($self->_current_hit, $self->analysis_method, $self->rfam,
                   $self->covariance_model, $self->desc_tag, $self->source_tag,
                   $self->motif_tag);
                my $ver = $self->program_version || '';
                my $qid = $name;
                if ($name =~ m{(?:gb|gi|emb|dbj|sp|pdb|bbs|ref|lcl)\|(\d+)((?:\:|\|)\w+\|(\S*.\d+)\|)?}xms) {
                    $qid = $1; 
                }
                my $fp = Bio::SeqFeature::FeaturePair->new();
                my $strlen = $hsp->{'model'} =~ tr{A-Za-z}{A-Za-z}; # gaps don't count
                my $qf = Bio::SeqFeature::Generic->new( -primary_tag => $mt,
                              -source_tag  => "$st $ver",
                              -display_name => $cm || '',
                              -score       => $score,
                              -start       => 1,
                              -end         => $strlen,
                              -seq_id      => $rfam || '',
                              -strand      => 0, # covariance model does not have a strand
                            );
                my $hf = Bio::SeqFeature::Generic->new( -primary_tag => $mt,
                              -source_tag  => "$st $ver",
                              -display_name => $dt || '',
                              -score       => $score,
                              -start       => $start,
                              -end         => $end,
                              -seq_id      => $qid,
                              -strand      => $strand
                            );
                $fp->feature1($qf);
                $fp->feature2($hf); # should emphasis be on the hit?
                $fp->add_tag_value('secstructure', $hsp->{'structure'});
                $fp->add_tag_value('model', $hsp->{'model'});
                $fp->add_tag_value('midline', $hsp->{'midline'});
                $fp->add_tag_value('hit', $hsp->{'hit'});
                $fp->add_tag_value('seq_name', $name);
                $fp->display_name($dt);
                return $fp;
            } else {
                next PARSER;
            }
        }
    }
    return (defined($line)) ? 1 : 0;
}

sub _current_hit {
    my $self = shift;
    return $self->{'_currhit'} = shift if @_;
    return $self->{'_currhit'};
}

1;
