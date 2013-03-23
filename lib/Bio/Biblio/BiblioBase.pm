package Bio::Biblio::BiblioBase;
use utf8;
use strict;
use warnings;

use parent qw(Bio::Root::Root);

# ABSTRACT: an abstract base for other biblio classes
# AUTHOR:   Martin Senger <senger@ebi.ac.uk>
# OWNER:    2002 European Bioinformatics Institute
# LICENSE:  Perl_5

=head1 SYNOPSIS

 # do not instantiate this class directly

=head1 DESCRIPTION

It is a base class where all other biblio data storage classes inherit
from. It does not reflect any real-world object, it exists only for
convenience, in order to have a place for shared code.

=head2 Accessors

All attribute names can be used as method names. When used without any
parameter the method returns current value of the attribute (or
undef), when used with a value the method sets the attribute to this
value and also returns it back. The set method also checks if the type
of the new value is correct.

=head2 Custom classes

If there is a need for new attributes, create your own class which
usually inherits from I<Bio::Biblio::Ref>. For new types of providers
and journals, let your class inherit directly from this
I<Bio::Biblio::BiblioBase> class.

=cut

our $AUTOLOAD;

=internal _accessible

This method should not be called here; it should be implemented by a subclass
=cut

sub _accessible { shift->throw_not_implemented(); }

=internal _attr_type

This method should not be called here; it should be implemented by a subclass
=cut

sub _attr_type { shift->throw_not_implemented(); }

=internal AUTOLOAD

Deal with 'set_' and 'get_' methods
=cut

sub AUTOLOAD {
    my ($self, $newval) = @_;
    if ($AUTOLOAD =~ /.*::(\w+)/ && $self->_accessible ("_$1")) {
        my $attr_name = "_$1";
        my $attr_type = $self->_attr_type ($attr_name);
        my $ref_sub =
            sub {
                my ($this, $new_value) = @_;
                return $this->{$attr_name} unless defined $new_value;

                # here we continue with 'set' method
                my ($newval_type) = ref ($new_value) || 'string';
                my ($expected_type) = $attr_type || 'string';
#               $this->throw ("In method $AUTOLOAD, trying to set a value of type '$newval_type' but '$expected_type' is expected.")
                $this->throw ($this->_wrong_type_msg ($newval_type, $expected_type, $AUTOLOAD))
                    unless ($newval_type eq $expected_type) or
                      UNIVERSAL::isa ($new_value, $expected_type);

                $this->{$attr_name} = $new_value;
                return $new_value;
            };

        no strict 'refs';
        *{$AUTOLOAD} = $ref_sub;
        use strict 'refs';
        return $ref_sub->($self, $newval);
    }

    $self->throw ("No such method: $AUTOLOAD");
}

=method new

The I<new()> class method constructs a new biblio storage object.  It
accepts list of named arguments - the same names as attribute names
prefixed with a minus sign. Available attribute names are listed in
the documentation of the individual biblio storage objects.
=cut

sub new {
    my ($caller, @args) = @_;
    my $class = ref ($caller) || $caller;

    # create and bless a new instance
    my ($self) = $class->SUPER::new (@args);

    # make a hashtable from @args
    my %param = @args;
    @param { map { lc $_ } keys %param } = values %param; # lowercase keys

    # set all @args into this object with 'set' values;
    # change '-key' into '_key', and making keys lowercase
    my $new_key;
    foreach my $key (keys %param) {
        ($new_key = $key) =~ s/-/_/og;   # change it everywhere, why not
        my $method = lc (substr ($new_key, 1));   # omitting the first '_'
        no strict 'refs';
        $method->($self, $param { $key });
    }

    # done
    return $self;
}

=internal _wrong_type_msg

Set methods test whether incoming value is of a correct type;
here we return message explaining it
=cut

sub _wrong_type_msg {
    my ($self, $given_type, $expected_type, $method) = @_;
    my $msg = 'In method ';
    if (defined $method) {
        $msg .= $method;
    } else {
        $msg .= (caller(1))[3];
    }
    return ("$msg: Trying to set a value of type '$given_type' but '$expected_type' is expected.");
}

=internal print_me

Probably just for debugging
TBD: to decide...
=cut

sub print_me {
    my ($self) = @_;
    require Data::Dumper;
    return Data::Dumper->Dump ( [$self], ['Citation']);
}

1;
