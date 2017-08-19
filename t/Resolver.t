#!/usr/bin/env perl

use strict;
use warnings;

use Log::Any::Adapter ('Stdout', log_level => 'debug');
use Template::Resolver;
use Test::More tests => 4;

BEGIN {use_ok('Template::Resolver')}

sub resolver {
    return Template::Resolver->new(@_);
}

is( resolver(
        {   employees => [
                {   name   => 'Bob',
                    awards => [
                        {type => 'BEST',          received => 2},
                        {type => 'PARTICIPATION', received => 12}
                    ]
                },
                {   name   => 'Jane',
                    awards => [
                        {type => 'BEST',          received => 7},
                        {type => 'PARTICIPATION', received => 5}
                    ]
                },
            ]
        }
        )->resolve(
        key     => 'T',
        content => '${for <emp> in T{employees}}'
            . '${for <awd> in T{<emp>.awards}}'
            . '${T{<emp>.name}} got ${T{<awd>.received}} ${T{<awd>.type}} awards' . "\n"
            . '${end <awd>}'
            . '${end <emp>}'
        ),
    "Bob got 2 BEST awards\n"
        . "Bob got 12 PARTICIPATION awards\n"
        . "Jane got 7 BEST awards\n"
        . "Jane got 5 PARTICIPATION awards\n",
    'Simple placeholder'
);

is(resolver({a => {value => '_VALUE_'}})->resolve(key => 'T', content => 'A${T{a.value}}A'),
    'A_VALUE_A', 'Simple placeholder');

is( resolver(
        {   web => {
                context_path => '/foo',
                hostname     => 'example.com',
                https        => 1,
                port         => 8443
            }
        },
        additional_transforms => {
            web_url => sub {
                my ($self, $value) = @_;

                my $url =
                    $self->_property("$value.https")
                    ? 'https://'
                    : 'http://';

                $url .= $self->_property("$value.hostname")
                    || croak("hostname required for web_url");

                my $port = $self->_property("$value.port");
                $url .= ":$port" if ($port);

                $url .= $self->_property("$value.context_path") || '';

                return $url;
            }
        }
        )->resolve(key => 'T', content => 'A${T_web_url{web}}A'),
    'Ahttps://example.com:8443/fooA',
    'Custom transformer'
);
