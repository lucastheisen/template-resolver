use strict;
use warnings;

eval {
    require Log::Log4perl;
    Log::Log4perl->easy_init($Log::Log4perl::ERROR);
    $Log::Log4perl::ERROR if (0); # prevent used only once warning
};
if ($@) {
}

use Test::More tests => 13;

BEGIN {use_ok('Template::Overlay')}

use File::Basename;
use File::Find;
use File::Temp;
use Template::Overlay;
use Template::Resolver;

my $test_dir = dirname(File::Spec->rel2abs($0));

sub test_dir {
    return File::Spec->catdir($test_dir, @_);
}

sub test_file {
    return File::Spec->catfile($test_dir, @_);
}

sub overlay {
    my ($config, $overlays) = @_;

    my $dir = File::Temp->newdir();
    Template::Overlay
        ->new(
            test_dir('base'),
            Template::Resolver->new($config),
            key => 'T')
        ->overlay($overlays, to=>$dir);

    my %results = ();
    find(
        sub {
            if (-f $File::Find::name && $File::Find::name =~ /^$dir\/(.*)$/) {
                $results{$1} = do {local(@ARGV, $/) = $_; <>};
            }
        }, $dir);
    return \%results;
}


my $config = {
    what=>{this=>{'is'=>'im not sure'}},
    todays=>{random=>{thought=>'something awesome'}}
};
my $results = overlay($config, test_dir('overlay1'));
like($results->{'a.txt'},
    qr/This is a test\.(?:\r|\n|\r\n)/, 
    'overlay1 a.txt');
like($results->{'subdir/b.txt'},
    qr/Random thought for today is: something awesome(?:\r|\n|\r\n)/, 
    'overlay1 subdir/b.txt');
like($results->{'c.txt'},
    qr/Another file full of nonsense\.(?:\r|\n|\r\n)/, 
    'overlay1 c.txt');

$config = {
    what=>{this=>{'is'=>'im not sure'}},
    todays=>{random=>{thought=>'something awesome'}}
};
$results = overlay($config, test_dir('overlay2'));
like($results->{'a.txt'},
    qr/This is a im not sure\.(?:\r|\n|\r\n)/, 
    'overlay2 a.txt');
like($results->{'subdir/b.txt'},
    qr/Random thought for today is: fumanchu\.(?:\r|\n|\r\n)/, 
    'overlay2 subdir/b.txt');
like($results->{'c.txt'},
    qr/Another file full of nonsense\.(?:\r|\n|\r\n)/, 
    'overlay2 c.txt');

$config = {
    what=>{this=>{'is'=>'im not sure'}},
    todays=>{random=>{thought=>'something awesome'}}
};
$results = overlay($config, [test_dir('overlay1'), test_dir('overlay2')]);
like($results->{'a.txt'},
    qr/This is a im not sure\.(?:\r|\n|\r\n)/, 
    'overlay1,overlay2 a.txt');
like($results->{'subdir/b.txt'},
    qr/Random thought for today is: something awesome(?:\r|\n|\r\n)/, 
    'overlay1,overlay2 subdir/b.txt');
like($results->{'c.txt'},
    qr/Another file full of nonsense\.(?:\r|\n|\r\n)/, 
    'overlay1,overlay2 c.txt');

$config = {
    what=>{this=>{'is'=>'im not sure'}},
    todays=>{random=>{thought=>'something awesome'}}
};
$results = overlay($config, [test_dir('overlay2'), test_dir('overlay1')]);
like($results->{'a.txt'},
    qr/This is a im not sure\.(?:\r|\n|\r\n)/, 
    'overlay2,overlay1 a.txt');
like($results->{'subdir/b.txt'},
    qr/Random thought for today is: something awesome(?:\r|\n|\r\n)/, 
    'overlay2,overlay1 subdir/b.txt');
like($results->{'c.txt'},
    qr/Another file full of nonsense\.(?:\r|\n|\r\n)/, 
    'overlay2,overlay1 c.txt');
