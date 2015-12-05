use strict;
use warnings;

package Template::Transformer;

# ABSTRACT: Transformer used by Template::Resolver
# PODNAME: Template::Transformer

use Carp;
use Data::Dumper;
use Hash::Util qw(lock_hashref);
use Log::Any;
use Safe;

my $logger = Log::Any->get_logger();

sub new {
    return bless( {}, shift )->_init( @_ );
}

sub _boolean {
    my ($self, $value) = @_;
    return $self->_default( $value ) ? 'true' : 'false';
}

sub _default {
    my ($self, $value) = @_;
    my ($key, $default) = split( /:/, $value, 2 );
    my $return_value = $self->_property( $key );
    $return_value = $default unless ( defined( $return_value ) );
    croak( "undefined value without default, '$value'" )
        unless ( defined( $return_value ) );
    return $return_value;
}

sub _env {
    my ($self, $value) = @_;
    return $ENV{$value};
}

sub _init {
    my ($self, $os, $properties) = @_;
    $logger->debug( 'initializing transformer for ', $os );
    
    $self->{os} = $os;
    $self->{properties} = $properties;
    
    $self->{wrapped_transforms} = {
        'boolean' => $self->_wrap_transform( \&_boolean ),
        'default' => $self->_wrap_transform( \&_default ),
        'env' => $self->_wrap_transform( \&_env ),
        'os_path' => $self->_wrap_transform( \&_os_path ),
        'perl' => $self->_wrap_transform( \&_perl ),
        'xml_escape' => $self->_wrap_transform( \&_xml_escape )
    };
    lock_hashref( $self->{wrapped_transforms} );
    
    return $self;
}

sub _safe_compartment {
    my ($self) = @_;
    if ( !$self->{safe_compartment} ) {
        $self->{safe_compartment} = Safe->new();
        *{$self->{safe_compartment}->varglob( 'property' )} = 
            $self->_wrap_transform( \&_property );
        foreach my $transform ( keys( %{$self->{wrapped_transforms}} ) ) {
            *{$self->{safe_compartment}->varglob( $transform )} = 
                $self->{wrapped_transforms}{$transform};
        }
    }
    
    return $self->{safe_compartment};
}

sub _property {
    my ($self, $key) = @_;
    return $self->{properties}{$key};
}

sub _os_path {
    my ($self, $value) = @_;
    $value = $self->_default( $value );
    if ( $self->{os} eq 'cygwin' ) {
        $value =~ s/\\/\\\\/g;
        $value= `cygpath --absolute --mixed $value 2> /dev/null`;
        chomp( $value );
    }
    return $value;
}

sub _perl {
    my ($self, $value) = @_;
    return $self->_safe_compartment()->reval( $value );
}

sub transform {
    my ($self, $value, $transform_name) = @_;
    $transform_name ||= 'default';
    $logger->debug( 'applying [', $transform_name, '] to [', $value, ']' );

    my $transform = $self->{wrapped_transforms}{$transform_name};
    croak( "unknown transform '$transform'" ) unless ( $transform );
    return &$transform( $value );
}

sub _xml_escape {
    my ($self, $value) = @_;
    $value = $self->_default( $value );
    $value =~ s/&/&amp;/sg;
    $value =~ s/</&lt;/sg;
    $value =~ s/>/&gt;/sg;
    $value =~ s/"/&quot;/sg;
    $value =~ s/'/&apos;/sg;
    return $value;
}

sub _wrap_transform {
    my ($self, $transform) = @_;
    return sub {
        &$transform( $self, @_ );
    }
}

1;

__END__

=for Pod::Coverage new transform
