#!perl
## no critic (Modules::ProhibitMultiplePackages)

use strict;
use warnings;

use utf8;
use Test2::V0;
set_encoding('utf8');

# Add t/lib to @INC
use FindBin 1.51 qw( $RealBin );
use File::Spec;
my $lib_path;
BEGIN {
    $lib_path = File::Spec->catdir(($RealBin =~ /(.+)/msx)[0], q{.}, 'lib');
}
use lib "$lib_path";

use Test::WWW::Mechanize::PSGI;
use HTTP::Request::Common;
use Crypt::JWT qw(encode_jwt decode_jwt);
use JSON qw( to_json from_json );

# Activate for testing
use Log::Any::Adapter ('Stdout', log_level => 'debug' );

use Dancer2::Plugin::JobScheduler::TestingUtils qw( :all );
use Test::Database::Temp;
use Data::Dumper;

# Test databases
# my @drivers = qw( Pg );
# my %test_dbs;

BEGIN {
    # Create test databases
    # %test_dbs = build_test_dbs( @drivers );

    my $driver = 'Pg';
    my $test_db = Database::Temp->new(
        driver => $driver,
        cleanup => 1,
        init => sub {
            my ($dbh, $name) = @_;
            init_db( $driver, $dbh, $name);
        },
    );
    my %database_plugin_config = (
        connections => {
            theschwartz_db1 => {
                db_2_dancer2_database_plugin_config( $test_db ),
            },
        },
    );

    {
        package Dancer2::Plugin::Database::MyHandle;
        use Dancer2;
        use Dancer2::Plugin::Database;
        use Dancer2::Plugin::JobScheduler::TestingUtils qw( :all );
        BEGIN {
            set log => 'debug';
            set plugins => {
                Database => \%database_plugin_config,
            };
        }
        sub get_dbh {
            my ($name) = @_;
            return database($name);
        }
        1;
    }

}

my %job_scheduler_plugin_config = (
    default => 'theschwartz',
    schedulers => {
        theschwartz => {
            client => 'TheSchwartz',
            parameters => {
                handle_uniqkey => 'acknowledge',
                databases => {
                    theschwartz_db1 => {
                        prefix => q{},
                        use_dancer2_plugin_database => 1,
                        # dbh_callback => \&Dancer2::Plugin::Database::MyHandle::get_dbh,
                    },
                }
            }
        }
    }
);

{
    package TestProgram;
    use Dancer2;
    use HTTP::Status qw( :constants status_message );
    BEGIN {
        set log => 'debug';
        set plugins => {
            JobScheduler => \%job_scheduler_plugin_config,
        };
    }
    use Dancer2::Plugin::JobScheduler;
    use Data::Dumper;

    set serializer => 'JSON';

    post qr{/submit_job/(?<task_name>[[:word:]_-]{1,})$}msx => sub {
        my $h = request_data;
        my %r = submit_job(
            client => 'theschwartz',
            job => {
                task => captures->{task_name},
                args => $h->{'args'},
                opts => $h->{'opts'},
            },
        );
        status HTTP_OK;
        return \%r;
    };

    get qr{/list_jobs/(?<task_name>[[:word:]_-]{1,})$}msx => sub {
        my %r = list_jobs(
            client => 'theschwartz',
            search_params => {
                task => captures->{task_name},
            },
        );
        status HTTP_OK;
        return \%r;
    };

}

my $app = TestProgram->to_app;
is(ref $app, 'CODE', 'Initialized the test app');

# Activate web app
my $mech = Test::WWW::Mechanize::PSGI->new( app => $app );

# Submit a job with ID 1
$mech->post(q{/submit_job/task_2}, content => to_json({
        args => { name => 'My Name', age => 204 },
        opts => { unique_key => 'UNIQ_123' },
    }));
is( from_json($mech->content), { error => undef, status=>'OK',success=>1, id=>1, }, 'Correct return');

# Submit a job with ID 2
$mech->post(q{/submit_job/task_3}, content => to_json({
        args => { name => 'My Name', age => 204 },
        opts => { unique_key => 'UNIQ_123' },
    }));
is( from_json($mech->content), { error => undef, status=>'OK',success=>1, id=>2, }, 'Correct return');

# List jobs, get 1
$mech->get_ok(q{/list_jobs/task_3});
# diag $mech->content;
is( from_json($mech->content), {
            error => undef, status=>'OK',success=>1,
            jobs =>[
                {task=>'task_3',args=>{name=>'My Name',age=>204},opts=>{unique_key=>'UNIQ_123'},},
            ]
        }, 'Correct return');

# Create two jobs with the same unique key for task 'task_4'.
# The second job insert will not do anything.

# Submit a job with ID 3, task_4
$mech->post(q{/submit_job/task_4}, content => to_json({
        args => { name => 'My Name', age => 204 },
        opts => { unique_key => 'UNIQ_123' },
    }));
is( from_json($mech->content), {error=>undef,status=>'OK',success=>1,id=>3}, 'Correct return');

# Submit same job again. Get back the same job id.
$mech->post(q{/submit_job/task_4}, content => to_json({
        args => { name => 'My Name', age => 204 },
        opts => { unique_key => 'UNIQ_123' },
    }));
is( from_json($mech->content), { error => undef, status=>'OK',success=>1, id=>3}, 'Correct return');
done_testing;
