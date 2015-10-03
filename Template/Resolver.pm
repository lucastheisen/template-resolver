use strict;
use warnings;

package Template::Resolver;

use Carp;
use Log::Log4perl;
use Template::Transformer;

my $logger = Log::Log4perl->get_logger();

sub new {
    return bless( {}, shift )->_init( @_ );
}

sub _entity_to_properties {
    my ($entity, $properties, $prefix) = @_;
    
    $properties = {} unless $properties;

    my $ref = ref( $entity );
    if ( $ref && $ref eq 'HASH' ) {
        foreach my $key ( keys( %{$entity} ) ) {
            _entity_to_properties( $entity->{$key}, $properties, 
                ($prefix ? "$prefix.$key" : $key) );
        }
    }
    elsif ( $ref && $ref eq 'ARRAY' ) {
        my $index = 0;
        foreach my $array_entity ( @{$entity} ) {
            _entity_to_properties( $array_entity, $properties, 
                ($prefix ? "$prefix\[$index\]" : "[$index]") );
            $index++;
        }
    }
    elsif ( $ref ) {
        croak( "unsupported ref type '$ref'" );
    }
    else {
        $properties->{$prefix} = $entity;
    }
    
    return $properties;
}

sub _get_property {
    my ($self, $value, $transform) = @_;
    my $transformed = $self->{transformer}->transform( $value, $transform );
    croak( "undefined value $value" . ($transform ? ", using transform $transform" : '') )
        unless ( defined( $transformed ) );
    return $transformed;
}

sub _init {
    my ($self, $entity, $os) = @_;
    
    croak( "missing os" ) if ( ! $os );
    $logger->debug( 'creating new Resolver' );

    $self->{entity} = $entity;
    $self->{transformer} = Template::Transformer->new( 
        $os, _entity_to_properties( $entity ) );

    return $self;
}

sub resolve {
    my ($self, $in, $key) = @_;
    
    my $contents;
    if ( ref( $in ) eq 'GLOB' ) {
        $contents = do { local( $/ ) = undef; <$in> };
    }
    else {
        $contents = do { local( @ARGV, $/ ) = $in; <> };
    }

    $contents =~ s/\${$key(?:_(.*?))?{(.*?)}}/$self->_get_property($2,$1)/eg;
    return $contents;
}

1;