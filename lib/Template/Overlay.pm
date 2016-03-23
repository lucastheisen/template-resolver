use strict;
use warnings;

package Template::Overlay;

# ABSTRACT: A powerful, and simple, library for resolving placeholders in templated files
# PODNAME: Template::Resolver

use Carp;
use File::Copy qw(cp);
use File::Find;
use File::Path qw(make_path);
use File::Spec;
use File::stat;
use Fcntl ':mode';
use Log::Any;
use Template::Overlay;

my $logger = Log::Any->get_logger();

sub new {
    return bless({}, shift)->_init(@_);
}

sub _init {
    my ($self, $base, $resolver, %options) = @_;
    
    $self->{base} = File::Spec->rel2abs($base);
    $self->{resolver} = $resolver;
    $self->{key} = $options{key};

    $logger->debug('new overlay [', $self->{base}, ']');

    return $self;
}

sub _overlay_files {
    my ($self, $overlays) = @_;

    my %overlay_files = ();
    foreach my $overlay (ref($overlays) eq 'ARRAY' ? @$overlays : ($overlays)) {
        $overlay = File::Spec->rel2abs($overlay);
        find(
            sub {
                if (-f $File::Find::name && $File::Find::name =~ /^$overlay\/(.*[^~])$/) {
                    $overlay_files{$1} = $File::Find::name;
                }
            }, $overlay);
    }

    return %overlay_files;
}

sub overlay {
    my ($self, $overlays, %options) = @_;

    my %overlay_files = $self->_overlay_files($overlays);
    my $destination = $self->{base};
    if ($options{to} && $options{to} ne $self->{base}) {
        $destination = File::Spec->rel2abs($options{to});
        my $length = length($self->{base});
        find(
            sub {
                my $relative = substr($File::Find::name, $length);
                if (-d $File::Find::name) {
                    make_path(File::Spec->catdir($destination, $relative));
                }
                if (-f $File::Find::name) {
                    my $template = delete($overlay_files{$relative});
                    my $file = File::Spec->catfile($destination, $relative);
                    if ($template) {
                        $self->_resolve($template, $file);
                    }
                    else {
                        cp($_, $file);
                    }
                }
            }, $self->{base});
    }
    foreach my $relative (keys(%overlay_files)) {
        my $file = File::Spec->catfile($destination, $relative);
        make_path((File::Spec->splitpath($file))[1]);
        $self->_resolve($overlay_files{$relative}, $file);
    }
}

sub _resolve {
    my ($self, $template, $file) = @_;

    $logger->info('processing [', $template, '] -> [', $file, ']');
    open(my $handle, '>', $file) || croak("open $file failed: $!");
    eval {
        print($handle 
            $self->{resolver}->resolve(
                filename => $template, 
                ($self->{key} ? (key => $self->{key}) : ()) ));
    };
    my $error = $@;
    close($handle);
    croak($error) if ($error);
}

1;

__END__
=head1 SYNOPSIS

  use Template::Overlay;
  use Template::Resolver;

  my $overlay_me = Template::Overlay->new(
      '/path/to/base/folder',
      Template->Resolver->new($entity),
      key => 'REPLACEME');
  $overlay_me->overlay(
      ['/path/to/template/base','/path/to/another/template/base'],
      to => '/path/to/processed');

=head1 DESCRIPTION

This provides the ability ot overlay a set of files with a set of resolved templates.
It uses L<Template::Resolver> to resolve each file.

=constructor new($base, $resolver, [%options])

Creates a new overlay processor for the files in C<$base> using C<$resolver> to process
the template files. The available options are:

=over 4

=item key

The template key used by C<Template::Resolver-E<lt>resolve>.

=back

=method overlay($overlays, [%options])

Overlays the C<$base> directory (specified in the constructor) with the resolved 
templates from the directories in C<$overlays>.  C<$overlays> can be either a path,
or an array reference containing paths.  If multiple C<$overlays> contain the same 
template, the last one in the array will take precedence.  The available options are:

=over 4

=item to

If specified, the files in C<$base> will not be not be modified.  Rather, they will
be copied to the path specified by C<$to> and the overlays will be processed on top
of that directory.

=back

=head1 SEE ALSO
Template::Resolver
Template::Transformer
https://github.com/lucastheisen/template-resolver
