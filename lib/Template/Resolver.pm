use strict;
use warnings;

package Template::Resolver;

# ABSTRACT: A powerful, and simple, library for resolving placeholders in templated files
# PODNAME: Template::Resolver

use Carp;
use Log::Any;
use Scalar::Util qw(blessed);
use Template::Transformer;

my $logger = Log::Any->get_logger();

sub new {
    return bless({}, shift)->_init(@_);
}

sub _entity_to_properties {
    my ($entity, $properties, $prefix) = @_;

    $properties = {} unless $properties;

    my $ref = ref($entity);
    if (($ref && $ref eq 'HASH') || blessed($entity)) {
        foreach my $key (keys(%{$entity})) {
            _entity_to_properties($entity->{$key}, $properties,
                ($prefix ? "$prefix.$key" : $key));
        }
    }
    elsif ($ref && $ref eq 'ARRAY') {
        my $index = 0;
        foreach my $array_entity (@{$entity}) {
            _entity_to_properties($array_entity, $properties,
                ($prefix ? "$prefix\[$index\]" : "[$index]"));
            $index++;
        }
    }
    elsif ($ref) {
        croak("unsupported ref type '$ref'");
    }
    else {
        $properties->{$prefix} = $entity;
    }

    return $properties;
}

use Data::Dumper;

sub _get_property {
    my ($self, $value, $transform) = @_;
    my $transformed = $self->{transformer}->transform($value, $transform);
    croak("undefined value $value" . ($transform ? ", using transform $transform" : ''))
        unless (defined($transformed));
    return $transformed;
}

sub _init {
    my ($self, $entity, %options) = @_;

    my $os = $options{os} || $^O;

    $logger->debug('creating new Resolver');

    $self->{entity}      = $entity;
    $self->{transformer} = Template::Transformer->new(
        $os,
        _entity_to_properties($entity),
        (   $options{additional_transforms}
            ? (additional_transforms => $options{additional_transforms})
            : ()
        )
    );

    return $self;
}

sub _resolve_array_loop {
    my ($self, $loop_name, $property_name, $property_value, $content) = @_;
    my ($result, $key, $value) = ('', '', '');
    my $resolve = sub {
        return (!$_[0]) ? "${property_name}[${key}]" : ($_[0] eq 'key') ? $key : $value;
    };
    while (($key, $value) = each(@$property_value)) {
        my $line = $content;
        $line =~ s/\<$loop_name(?:\.(key|value))?>/$resolve->($1)/egs;
        $result = $result . $line;
    }
    return $result;
}

sub _resolve_hash_loop {
    my ($self, $loop_name, $property_name, $property_value, $content) = @_;
    my ($result, $key, $value) = ('', '', '');
    my $resolve = sub {
        return (!$_[0]) ? "${property_name}.${key}" : ($_[0] eq 'key') ? $key : $value;
    };
    while (($key, $value) = each(%$property_value)) {
        my $line = $content;
        $line =~ s/\$\{$loop_name(?:\.(key|value))?\}/$resolve->($1)/egs;
        $result = $result . $line;
    }
    return $result;
}

sub _resolve_loop {
    my ($self, $loop_name, $property_name, $content) = @_;
    my $property_value = $self->_get_value($property_name);
    my $result         = '';
    my $ref            = ref($property_value);
    if ($ref && $ref eq 'HASH') {
        $result =
            $self->_resolve_hash_loop($loop_name, $property_name, $property_value, $content);
    }
    elsif ($ref && $ref eq 'ARRAY') {
        $result =
            $self->_resolve_array_loop($loop_name, $property_name, $property_value, $content);
    }
    elsif ($ref) {
        croak("'$property_name': unsupported ref type '$ref'");
    }
    else {
        croak("'$property_name': does not exist");
    }
    return $result;
}

sub _resolve_loops {
    my ($self, $key, $content) = @_;
    my $done = 0;
    while (!$done) {
        my $converted = $content
            =~ s/\$\{for <(\S+)> in $key\{(.*?)\}\}(.*?)\$\{end <\1>\}/$self->_resolve_loop($1,$2,$3)/egs;
        $done = ($converted == 0);
    }
    return $content;
}

sub _get_value {
    my ($self, $key) = @_;
    my $val = $self->{entity};
    for my $token (split(/\./, $key)) {
        my ($name, $indices) = $token =~ /^(\w+)?((?:\[\d+\])*)$/;
        croak("Invalid entity: '$key'") if (!$name && !$indices);
        $val = $val->{$name} if ($name);
        if ($indices) {
            for my $index (split(/\]\[/, substr($indices, 1, length($indices) - 2))) {
                $val = $val->[$index];
            }
        }
    }
    return $val;
}

sub resolve {
    my ($self, %options) = @_;

    my $key = $options{key} || 'TEMPLATE';

    my $content;
    if ($options{content}) {
        $content = $options{content};
    }
    elsif ($options{handle}) {
        $content = do {local ($/) = undef; <$options{handle}>};
    }
    elsif ($options{filename}) {
        $content = do {local (@ARGV, $/) = $options{filename}; <>};
    }
    else {
        croak('Must provide one of [content, handle, filename]');
    }
    $content = $self->_resolve_loops($key, $content);
    $content =~ s/\$\{$key(?:_(.*?))?\{(.*?)\}\}/$self->_get_property($2,$1)/egs;
    return $content;
}

1;

__END__
=head1 SYNOPSIS

  use Template::Resolver;
  my $resolver = Template::Resolver->new($entity);
  $resolver->resolve(file => '/path/to/file', key => 'REPLACEME');

=head1 DESCRIPTION

This module provides a powerful way to resolve placeholders inside of a templated file.
It uses L<Template::Transformer> to interpolate the the placeholder values. The
provided template may refer to entity values directly (i.e.
C<${TEMPLATE{my.entity.value}}>) or through transformations (i.e.
C<${TEMPLATE{my.truthy}:boolean>).
You may also loop over hash and array entities like this (newlines and indentation
included for clarity):

  ${for <CLUB> in TEMPLATE{my.clubs}}$
      {for <MEMBER> in TEMPLATE{<CLUB>.members}}
          ${TEMPLATE{<MEMBER>.name>}} is a member of the ${TEMPLATE{<CLUB>.club_name}} club.
      ${end <MEMBER>}
  ${end <CLUB>}

=constructor new(\%entity, %options)

Creates a new resolver with properties from C<\%entity> and C<%options> if any.  The
available options are:

=over 4

=item additional_transforms

Additional custom transforms that will be added to the standard transforms.
Must be a hashref containing transform name to sub reference mappings.  
The sub reference(s) will be called as a method(s) with a single parameter
containing the contents of the placeholder.

=item os

The operating system path format used when resolving C<${TEMPLATE_os{xxx}}> placeholders.

=back

=method resolve(%options)

Will read the template and replace all placeholders prefixed by C<key>. One of the 
options C<content>, C<handle>, or C<filename> is required.  The available options are:

=over 4

=item content

A string containing templated content.

=item filename

The name of a file containing templated content.

=item handle

A handle to a file containing templated content.

=item key

The template key, defaults to C<TEMPLATE>.

=back

=head1 SEE ALSO
Template::Transformer
Template::Overlay
https://github.com/lucastheisen/template-resolver
