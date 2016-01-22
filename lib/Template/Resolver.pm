use strict;
use warnings;

package Template::Resolver;

# ABSTRACT: A powerful, and simple, library for resolving placeholders in templated files
# PODNAME: Template::Resolver

use Carp;
use Log::Any;
use Template::Transformer;

my $logger = Log::Any->get_logger();

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
    my ($self, $entity, %options) = @_;
    
    my $os = $options{os} || $^O;

    $logger->debug( 'creating new Resolver' );

    $self->{entity} = $entity;
    $self->{transformer} = Template::Transformer->new( 
        $os, _entity_to_properties( $entity ) );

    return $self;
}

sub resolve {
    my ($self, %options) = @_;

    my $key = $options{key} || 'TEMPLATE';
    
    my $content;
    if ( $options{content} ) {
        $content = $options{content}
    }
    elsif ( $options{handle} ) {
        $content = do { local( $/ ) = undef; <$options{handle}> };
    }
    elsif ( $options{filename} ) {
        $content = do { local( @ARGV, $/ ) = $options{filename}; <> };
    }
    else {
        croak( 'Must provide one of [content, handle, filename]' );
    }

    $content =~ s/\$\{$key(?:_(.*?))?\{(.*?)\}\}/$self->_get_property($2,$1)/egs;
    return $content;
}

1;

__END__
=head1 SYNOPSIS

  use Template::Resolver;
  my $resolver = Template::Resolver->new($entity);
  $resolver->resolve($file_handle_or_name, $template_prefix);

=head1 DESCRIPTION

This module provides a powerful way to resolve placeholders inside of a templated file.
It uses L<Template::Transformer> to interpolate the the placeholder values.

=constructor new(\%entity, %options)

Creates a new resolver with properties from C<\%entity> and C<%options> if any.  The
available options are:

=over 4

=item os

The operating system path format used when resolving C<${TEMPLATE_os{xxx}}> placeholders.

=back

=method resolve($file_handle_or_name, $placeholder_prefix)

Will read from C<$file_handle_or_name> replacing all placeholders prefixed by 
C<$placeholder_prefix>.

=head1 SEE ALSO
Template::Transformer
https://github.com/lucastheisen/template-resolver
