package Dancer2::Plugin::JobScheduler::Client::TheSchwartz;
## no critic (ControlStructures::ProhibitPostfixControls)

use strict;
use warnings;

# ABSTRACT: A front to the client of the job scheduler or other object via which the jobs are submitted

# VERSION: generated by DZP::OurPkgVersion

=pod

=encoding utf8

=head1 DESCRIPTION

Internal class.
Not to be used separately. Please see L<Dancer2::Plugin::JobScheduler>.

=cut

use Carp;
use English '-no_match_vars';
use Module::Load;
use Const::Fast;

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

use Moo;
use Dancer2::Plugin::Database;
use TheSchwartz::JobScheduler;
use TheSchwartz::JobScheduler::Job;

const my $DEFAULT_HANDLE_UNIQKEY => 'no_check';

=head1 PARAMETERS

=head2 config

All parameters for this job scheduler are passed through.

=cut

has config => (
    is          => 'ro',
    isa         => sub { croak if( ref $_[0] ne 'HASH' ) },
);

has _client => (
    is => 'lazy',
);
sub _build__client { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $c = $self->config;
    $log->debugf( 'config: %s', $c );
    my $handle_uniqkey = $c->{'handle_uniqkey'} // $DEFAULT_HANDLE_UNIQKEY;
    my $client = TheSchwartz::JobScheduler->new(
        databases => $c->{'databases'},
        opts => {
            handle_uniqkey => $handle_uniqkey,
        },
    );
    return $client;
}

=head2 submit_job $job

=cut

sub submit_job {
    my ($self, $job) = @_;
    $log->debugf('submit_job: %s', $job);
    croak 'No task name', if( ! $job->{'task'} );
    my $j = TheSchwartz::JobScheduler::Job->new;
    $j->funcname( $job->{'task'} );
    $j->arg( $job->{'args'} ) if $job->{'args'};
    $j->uniqkey( $job->{'opts'}->{'unique_key'} ) if $job->{'opts'}->{'unique_key'};
    $j->uniqkey( $job->{'opts'}->{'uniqkey'} ) if $job->{'opts'}->{'uniqkey'};
    $j->run_after( $job->{'opts'}->{'run_after'} ) if $job->{'opts'}->{'run_after'};

    my $job_id = $self->_client->insert( $j );
    my %r = (
        success => 1,
        status  => 'OK',
        error   => undef,
        id      => $job_id,
    );
    if( $job_id ) {
        return %r;
    }
    $r{success} = 0;
    $r{status}  = 'FAIL';
    $r{error}   = undef;
    return %r;
}

=head2 list_jobs $args

=cut

sub list_jobs {
    my ($self, $args) = @_;
    $log->debugf('list_jobs(%s)', $args);
    croak 'No task name', if( ! $args->{'task'} );

    my %arg;
    $arg{'funcname'} = $args->{'task'};
    $arg{'run_after'} = $args->{'run_after'} if exists $args->{'run_after'};
    $arg{'grabbed_until'} = $args->{'grabbed_until'} if exists $args->{'grabbed_until'};
    $arg{'coalesce'} = $args->{'coalesce'} if exists $args->{'coalesce'};

    my @jobs = $self->_client->list_jobs( \%arg );
    $log->debugf('list_jobs(): jobs: %s', \@jobs);
    my @r_jobs;
    foreach my $job (@jobs) {
        my %opts;
        $opts{'unique_key'} = $job->uniqkey if $job->uniqkey;
        push @r_jobs, {
            task => $args->{'task'},
            args => $job->arg,
            opts => \%opts,
        };
    }
    my %r = (
        success => 1,
        status  => 'OK',
        error   => undef,
        jobs    => \@r_jobs,
    );

    return %r;
}

1;