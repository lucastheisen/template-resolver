use strict;
use warnings;

eval {
    require Log::Log4perl;
    Log::Log4perl->easy_init($Log::Log4perl::ERROR);
    $Log::Log4perl::ERROR if (0); # prevent used only once warning
};
if ($@) {
}

use Test::More tests => 2;

BEGIN {use_ok('Template::Resolver')}

use Template::Resolver;

sub resolver {
    return Template::Resolver->new(@_);
}

is(resolver({a=>{value=>'_VALUE_'}})->resolve(key => 'T', content => 'A${T{a.value}}A'), 
    'A_VALUE_A', 
    'Simple placeholder');
