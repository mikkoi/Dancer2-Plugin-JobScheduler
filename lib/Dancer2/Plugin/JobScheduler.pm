package Dancer2::Plugin::JobScheduler;
use strict;
use warnings;

# ABSTRACT: Plugin for Dancer2 web app to send and query jobs in different job schedulers

# VERSION: generated by DZP::OurPkgVersion

=pod

=encoding utf8

=cut

#Lots of subs not covered by Pod::Coverage
#because they are inherited from Dancer2::Plugin.

=for Pod::Coverage ClassHooks PluginKeyword dancer_app execute_plugin_hook hook
=for Pod::Coverage list_jobs on_plugin_import plugin_args plugin_setting
=for Pod::Coverage register register_hook register_plugin request submit_job var


=head1 SYNOPSIS

    use Dancer2;
    BEGIN {
        my %plugin_config = (
            default => 'theschwartz',
            schedulers => {
                theschwartz => {
                    client => 'TheSchwartz',
                    parameters => {
                        handle_uniqkey => 'acknowledge',
                        dbh_callback => 'Database::ManagedHandle->instance',
                        databases => {
                            theschwartz_db1 => {
                                prefix => q{schema_name.},
                            },
                        }
                    }
                }
            }
        );
        set log => 'debug';
        set plugins => {
            JobScheduler => \%plugin_config,
        };
    }
    use Dancer2::Plugin::JobScheduler;

    set serializer => 'JSON';

    get q{/submit_job} => sub {
        my %r = submit_job(
            client => 'theschwartz',
            job => {
                task => 'task1',
                args => { name => 'My Name', age => 123 },
                opts => {},
            },
        );
        return to_json(\%r);
    };

    get q{/list_jobs} => sub {
        my %r = list_jobs(
            client => 'theschwartz',
            search_params => {
                task => 'task1',
            },
        );
        return to_json(\%r);
    };


=head1 DESCRIPTION

Dancer2::Plugin::JobScheduler is an interface to access different
L<job schedulers|https://en.wikipedia.org/wiki/Job_scheduler> in L<Dancer2>
web app.

Dancer2::Plugin::JobScheduler provides an interface to submit jobs
and query jobs currently in queue. As a L<Dancer2> plugin, it creates two
new commands in the web app: C<submit> and C<list_jobs>.

These commands abstract away the complexity of interfacing with a job scheduler.
User does not need to even know which job scheduler the website is using,
unless there are several in use, in which case they can be identified
by a short id.

A job scheduler is used to off-load CPU power or time consuming tasks from the web app
so that it can answer user's web requests as quickly as possible. One example
of tasks like these is sending a confirmation email. The email can be sent
after a delay, so the sending is scheduled off to a worker server somewhere else
where it will not burden the web app.

There are many job schedulers, and since their operation is separated from
Dancer2 web app, they can be implemented in any language, not just Perl,
the language of Dancer2.

Perl has several job schedulers, too. Most notable ones are
L<TheSchwartz> and L<Minion>. Also L<Gearman|http://gearman.org/>
is often mentioned among job schedulers because Gearman's
L<original version|https://en.wikipedia.org/wiki/Gearman>
was written in Perl though later it was rewritten in C.

Dancer2::Plugin::JobScheduler supports the following job schedulers:

=over 8

=item L<TheSchwartz>

=back

=head2 Using Dancer2::Plugin::JobScheduler with Dancer2::Plugin::Database

If you are doing database operations in a Dancer2 web app, you are probably
using L<Dancer2::Plugin::Database> to get the database handle you need.
You can use the same database handle with Dancer2::Plugin::JobScheduler.
This can be especially useful if you are doing database transactions.
If a transaction fails, you would probably want the scheduled job to
be removed as well.

You need to configure the databases just like you would normally
but without dbh_callback. You would provide the handle callback at the point
of calling C<submit_job()> or C<list_jobs()>.

    use Dancer2;
    use HTTP::Status qw( :constants status_message );
    BEGIN {
        set log => 'debug';
        set plugins => {
            JobScheduler => {
                default => 'theschwartz',
                schedulers => {
                    theschwartz => {
                        client => 'TheSchwartz',
                        parameters => {
                            databases => {
                                dancer_app_db => { },
                            },
                            dbh_callback => 'replaced-when-calling',
                        }
                    }
                },
            },
            Database => {
                connections => {
                    dancer_app_db => {
                        driver => SQLite,
                        database => '/tmp/dancer.sqlite'
                    },
                },
            },
        };
    }
    use Dancer2::Plugin::JobScheduler;
    use Dancer2::Plugin::Database;
    set serializer => 'JSON';
    get q{/submit_job} => sub {
        my %r = submit_job(
            client => 'theschwartz',
            job => {
                task => 'task1',
                args => { name => 'Mikko', age => 123 },
                opts => {},
            },
            opts => {
                # database is the keyword and command from
                # Dancer2::Plugin::Database. It takes one argument:
                # the database name, similar to our dbh_callback.
                dbh_callback => \&database,
            },
        );
        status HTTP_OK;
        return \%r;
    };


=head1 METHODS

=head2 submit

Submit a job with arguments to a job scheduler.
This can be as simple as following:

    submit_job( job => { task => 'task_name' });

In the example above, C<submit_job> uses the default scheduler.
This is enough when there is only one job scheduler.

Parameter B<job> can also have sub parameters:

=over 8

=item B<args> can be used to provide a hash of arguments to the task. These are task specific.

=item B<opts> can be used to provide a hash of options for the job scheduler. These are job scheduler specific and rarely used. They can be used, for example, to submit the job to a particular queue if there is priority queues in the system.

=back

    submit_job(
        job => {
            task => 'task_name',
            args => { name => 'Average Joe', age => 67 },
            opts => { run_after => time + (60*60) },
        },
    );

In the example above, the task is created with a delay of 60 minutes,
i.e. the job scheduler TheSchwartz will not attempt to run the task
before one hour is passed.

If you have several different job schedulers you can submit jobs to,
then use parameter B<client> to identify the one you want to use.
The client names are specified in the configuration.
You can also specify a default client.

    submit_job(
        client => 'theschwartz',
        job => {
            task => 'task_name',
        },
    );

C<submit_job> will return a hash which contains at least the following items:

=over 8

=item success, boolean. Was the operation successful?

=item status, string. Contains the status of the submit. In the case of success, this will be "OK".

=item error, string. Contains an error message if a message is available. Can also be undef.

=back

It can also contain other items depending on the job scheduler.
In the case of TheSchwartz, after a successful submit there will be item B<id>
which contains the id of the new job in the queue.

The following example showcases a very trivial way on how to integrate C<submit_job> into
a route:

    post q{/send_email} => sub {
        my $email = body_parameters->{email};
        # Remember to untaint input:
        ($email) = $email =~ m/ ( [a-zA-Z0-9]{1,} @ [a-zA-Z0-9]{1,} ) /msx;
        submit_job(
            job => {
                task => 'send_email',
                args => { email => $email },
            },
        );
    };


=head2 list_jobs

Return a list of all active jobs in the job scheduler.

Parameters:

=over 8

=item client, string. The scheduler name. Default specified in the configuration.

=item search_params, hash. These are job scheduler specific.

=back

    set serializer => q{JSON};
    get q{/list_jobs} => sub {
        my %r = list_jobs(
            client => 'theschwartz',
            search_params => {
                task => 'task1',
            },
        );
        return $r{'jobs'};
    };


=head1 CONFIGURATION

Dancer2::Plugin::JobScheduler uses Dancer2's configuration system.
You can either write your configuration in the config files
or specify it in the module.

The different job schedulers have their own configuration needs.
As an example we will cover here only TheSchwartz.


=head1 SEE ALSO

There is a Dancer2 plugin for Minion: L<Dancer2::Plugin::Minion>.

=cut

use Carp;
use English '-no_match_vars';
use Module::Load;

use Log::Any qw( $log ), hooks => { build_context => [ \&_build_context, ], };
use Log::Any::Adapter::Util;
sub _build_context {
    # my ($level, $category, $data) = @_;
    my %ctx;
    my @caller = Log::Any::Adapter::Util::get_correct_caller();
    $ctx{file} = $caller[1];
    $ctx{line} = $caller[2];
    return %ctx;
}

use Dancer2::Plugin 0.200002;

plugin_keywords qw(
    submit_job
    list_jobs
);

has default => (
    is          => 'ro',
    isa => sub {
        croak if(! ($_[0] =~ m/^[[:word:]]{1,}$/msx) );
    },
    from_config => 'default',
);

has schedulers => (
    is => 'ro',
    isa => sub {
        croak if(ref $_[0] ne 'HASH');
    },
    from_config => 'schedulers',
);

sub _verify_configuration {
    my ($self) = @_;
    if( $self->default ) {
        if( exists $self->schedulers->{ $self->default } ) {
            return $self->default;
        } else {
            my $e = 'Invalid value in config: plugins->JobScheduler->default: '
                . '\'%s\', no matching job scheduler';
            $log->errorf( $e, $self->default);
            croak sprintf $e, $self->default;
        }
    } else {
        if( scalar keys %{ $self->schedulers } > 1 ) {
            my $e = 'Default job queue missing in config. Must define '
                . 'default job queue when there is more than one job queue';
            $log->errorf( $e );
            croak $e;
        } elsif( scalar keys %{ $self->schedulers } <= 0 ) {
            my $e = 'Invalid config. Must have at least one job queue';
            $log->errorf( $e );
            croak $e;
        } else {
            return (keys %{ $self->schedulers })[0];
        }
    }
    return;
}


# A client (of a client) of the job queue
# or other object via which the jobs are submitted
has _clients => (
    is  => 'lazy',
    isa => sub {
        croak if(ref $_[0] ne 'HASH');
    },
);
sub _build__clients { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    $self->_verify_configuration();
    my %h;
    foreach my $key ( keys %{ $self->schedulers } ) {
        my $s = $self->schedulers->{$key};
        my $client_name = $s->{'client'} =~ m/::/msx
            ? $s->{'client'}
            : "Dancer2::Plugin::JobScheduler::Client::$s->{'client'}";

        # Does it exist?
        {
            local $EVAL_ERROR = $EVAL_ERROR;
            my $r = eval { load "$client_name"; 1; };
            if( ! $r || $EVAL_ERROR ) {
                my $e = 'Failed to load job queue client \'%s\', error: %s';
                $log->errorf( $e, $client_name, $EVAL_ERROR);
                croak sprintf $e, $client_name, $EVAL_ERROR;
            }
        }

        # Can we instantiate it?
        my $scheduler;
        {
            local $EVAL_ERROR = $EVAL_ERROR;
            my $r = eval {
                $scheduler = $client_name->new(
                    config => $s->{'parameters'},
                );
                1;
            };
            if( ! $r || $EVAL_ERROR ) {
                my $e = 'Failed to instantiate job queue client \'%s\', error: %s';
                $log->errorf( $e, $client_name, $EVAL_ERROR);
                croak sprintf $e, $client_name, $EVAL_ERROR;
            }
        }
        $h{ $key } = $scheduler;
    }
    return \%h;
}

sub submit_job {
    my ($self, %args) = @_;
    # my $log = sub { $self->log(@_); };
    # $log->(debug => 'submit_job(' . \%args . ')');

    my $client_key = $args{client} ? delete $args{client} : $self->default;
    # my $get_dbh = $args{get_dbh} ? $args{get_dbh} : undef;
    # $log->debugf('client_key: %s', $client_key);
    my $job = $args{job};
    my $opts = $args{opts} ? delete $args{opts} : {};
    # $log->debugf('_clients: %s', $self->_clients);
    my $client = $self->_clients->{$client_key};
    # $log->debugf('client: %s', $client);

    return $client->submit_job( $job, $opts );
}

sub list_jobs {
    my ($self, %args) = @_;
    my $client_key = $args{client} ? delete $args{client} : $self->default;
    my $search_params = $args{search_params};
    my $opts = $args{opts} ? delete $args{opts} : {};
    my $client = $self->_clients->{$client_key};
    return $client->list_jobs( $search_params, $opts );
}

1;
