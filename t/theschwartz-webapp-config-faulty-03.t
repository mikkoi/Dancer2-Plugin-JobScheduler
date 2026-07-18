#!perl

use strict;
use warnings;

use utf8;
use Test2::V0;
set_encoding('utf8');

use Test::WWW::Mechanize::PSGI;
use HTTP::Status qw( :constants );

# We have had problems with some JSON backends in keeping numbers numerical.
# So we force the backend by first loading Cpanel::JSON::XS
# and then explicitly demanding JSON to use it
BEGIN {
    use Cpanel::JSON::XS ();
    $ENV{PERL_JSON_BACKEND}='Cpanel::JSON::XS'; ## no critic (Variables::RequireLocalizedPunctuationVars)
}
use JSON; ## no critic (Community::PreferredAlternatives)

my %plugin_config = (
    schedulers => {
    }
);

{
    package Dancer2::Plugin::JobScheduler::Testing::TheSchwartz::WebApp::Config;
    use Dancer2;
    use HTTP::Status qw( :constants status_message );
    BEGIN {
        set log => 'debug';
        set plugins => {
            JobScheduler => \%plugin_config,
        };
    }
    use Dancer2::Plugin::JobScheduler;

    get q{/} => sub {
        status HTTP_OK;
        return 'OK';
    };

    get q{/list_jobs} => sub {
        my %r = list_jobs(
            client        => 'theschwartz',
            search_params => {
                task => 'task1',
            },
        );
        status HTTP_OK;
        return to_json( \%r, { utf8 => 1, canonical => 1, } );
    };
}

my $app = Dancer2::Plugin::JobScheduler::Testing::TheSchwartz::WebApp::Config->to_app;
is (ref $app, 'CODE', 'Got the test app');

my $json = JSON->new->utf8(1)->canonical(1);

# Activate web app
my $mech = Test::WWW::Mechanize::PSGI->new( app => $app );

$mech->get_ok(q{/});
$mech->content_is(q{OK}, 'Correct return');

# List jobs fails because of invalid config.
# N.B. The config is only read now, not at ->to_app() because
# the plugin is lazy loading.
$mech->get(q{/list_jobs});
# Route exception: Invalid config. Must have at least one job queue
$mech->status(HTTP_INTERNAL_SERVER_ERROR);

done_testing;
