use strict;
use warnings;

eval {
    require Log::Log4perl;
    Log::Log4perl->easy_init($Log::Log4perl::ERROR);
    $Log::Log4perl::ERROR if (0); # prevent used only once warning
};
if ($@) {
}

use Test::More tests => 3;

BEGIN {use_ok('Template::Resolver')}

use Template::Resolver;

sub resolver {
    return Template::Resolver->new(@_);
}

is(resolver({a=>{value=>'_VALUE_'}})->resolve(key => 'T', content => 'A${T{a.value}}A'), 
    'A_VALUE_A', 
    'Simple placeholder');

is(resolver(
    {
        web => {
            context_path => '/foo',
            hostname => 'example.com',
            https => 1,
            port => 8443
        }
    },
    additional_transforms => {
        web_url => sub {
            my ($self, $value) = @_;

            my $url = $self->_property("$value.https") 
                ? 'https://' 
                : 'http://';

            $url .= $self->_property("$value.hostname")
                || croak("hostname required for web_url");

            my $port = $self->_property("$value.port");
            $url .= ":$port" if ($port);

            $url .= $self->_property("$value.context_path") || '';

            return $url;
        }
    })->resolve(key => 'T', content => 'A${T_web_url{web}}A'), 
    'Ahttps://example.com:8443/fooA', 
    'Custom transformer');
