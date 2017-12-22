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

sub _resolve_loop {
    my ($self, $template_key, $loop_name, $property_name, $content) = @_;
    my $property_value = $self->_get_value($property_name);
    my $result         = '';
    my $ref            = ref($property_value);
    my ($replacer, $key_match, @keys);

    if ($ref && $ref eq 'HASH') {
        $replacer  = sub {return $_[1] ? $_[0] : "${property_name}.${_[0]}"};
        $key_match = "key";
        @keys      = sort(keys(%$property_value));
    }
    elsif ($ref && $ref eq 'ARRAY') {
        $replacer  = sub {return $_[1] ? $_[0] : "${property_name}[${_[0]}]"};
        $key_match = "ix";
        @keys      = keys(@$property_value);
    }
    elsif ($ref) {
        croak("'$property_name': cannot loop on unsupported ref type '$ref'");
    }
    else {
        croak("'$property_name': does not exist");
    }

    my $resolve_template = sub {
        my ($text, $key) = @_;
        if ($text eq "\$\{\Q$template_key\E<\Q$loop_name\E\.\Q$key_match\E\}\}") {
            $text = $key;
        }
        else {
            $text =~ s/<\Q$loop_name\E(\.\Q$key_match\E)?>/$replacer->($key,$1)/egs;
        }
        return $text;
    };

    foreach my $key (@keys) {
        my $line = $content;
        $line =~ s/\$\{$template_key<\Q$loop_name\E\.\Q$key_match\E>\}/$key/egs;
        $line =~ s/(\$\{$template_key.*?\}\})/$resolve_template->($1, $key)/egs;
        $result = $result . $line;
    }

    return $result;
}

sub _resolve_loops {
    my ($self, $key, $content) = @_;
    my $done = 0;
    while (!$done) {
        my $converted = $content
            =~ s/\$\{$key<(\S+)>:\{(.*?)\}\}(.*?)\$\{$key<\1>:end\}/$self->_resolve_loop($key,$1,$2,$3)/egs;
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
  # Basic example
  use Template::Resolver;
  my $resolver = Template::Resolver->new($entity);
  $resolver->resolve(file => '/path/to/file', key => 'REPLACEME');

  # More complete example
  use Template::Resolver;

  $java_properties_file = <<'EOF';

    # Simple value that will error if not present
    server_port = ${TEMPLATE{app.port}}

    # Simple value with a default (no error if not present)
    context_path = ${TEMPLATE{app.context_path:/myapp}}

    # Get an env var
    http_proxy = ${TEMPLATE_env{HTTP_PROXY}}

    # Translate a cygwin path with error if not present
    module_jar = ${TEMPLATE_os{app.module_addon1}}

    # Translate a cygwin path with default
    module_jar = ${TEMPLATE_os{app.module_addon2:/var/local/lib/mymodule.jar}}

    # Escape some xml (with blank default)
    html_header = ${TEMPLATE_xml_escape{app.header:}}

    # Run some perl
    https_enabled = ${TEMPLATE_perl{ property(app.use_https) ? 'true' : 'false'}}
    https_proxy = ${TEMPLATE_perl{ sprintf( 'https://%s:%d/', $ENV{HTTPS_PROXY_HOST}, $ENV{HTTPS_PROXY_PORT} )}}

    # Custom stuff
    db_user = ${TEMPLATE_customfetch{ 'dbuser' }}

  EOF

  my $entity = {
      app => {
          port => 80,
          module_addon1 => '/var/local/lib/mymodule.jar',
          use_https => 0,
      }
  };

  my $resolver = Template::Resolver->new( $entity, additional_transforms => {
      customfetch => sub {
          #Do something here
          return 'mydbuser';
      }
  });
  my $transformed_result = $resolver->resolve( content => $java_properties_file );

=head1 DESCRIPTION

This module provides a powerful way to resolve placeholders inside of a templated file.
It uses L<Template::Transformer> to interpolate the the placeholder values. The
provided template may refer to entity values directly (i.e.
C<${TEMPLATE{my.entity.value}}>) or through transformations (i.e.
C<${TEMPLATE_perl{property("my.truthy") ? "true" : "false"}}>).
You may also loop over hash and array entities like this (newlines and indentation
included for clarity):

  ${TEMPLATE<CLUB>:{my.clubs}}$
      {TEMPLATE<MEMBER>:{<CLUB>.members}}
          ${TEMPLATE{<MEMBER>.name}} is a member of the ${TEMPLATE{<CLUB>.club_name}} club.
      ${TEMPLATE<MEMBER>:end}
  ${TEMPATE<CLUB>:end}
  
You may access the key when iterating over hashes:

  ${TEMPLATE<RESOURCE>:{my.resources}}
      Resource, ${TEMPLATE:<RESOURCE.key>} is ${TEMPLATE{<RESOURCE>.deployed_artifact}}
  ${TEMPLATE<RESOURCE>:end}
 
You may also access the index when iterating over arrays:

  ${TEMPLATE<CLUB>:{my.clubs}}
      Club at index ${TEMPLATE<CLUB.ix>} is ${TEMPLATE{<CLUB.name>}}
  ${TEMPLATE<CLUB>:end}
 
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
