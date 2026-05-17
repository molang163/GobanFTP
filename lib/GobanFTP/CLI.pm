package GobanFTP::CLI;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Scalar::Util qw(reftype);

use GobanFTP::AckPublisher qw(build_ack_for_target);
use GobanFTP::Listing qw(normalize_listing sort_event_basenames);
use GobanFTP::GameSpec qw(build_basename parse_basename);
use GobanFTP::MovePublisher qw(build_next_move_name normalize_action);
use GobanFTP::Projection qw(render_projection write_projection write_sgf_projection);
use GobanFTP::Redact qw(redact_text);
use GobanFTP::Replay qw(replay);
use GobanFTP::Store::Config qw(context_for_descriptor context_for_game_arg store_mode);

use constant {
    EXIT_SUCCESS    => 0,
    EXIT_USAGE      => 1,
    EXIT_VALIDATION => 2,
    EXIT_CONFLICT   => 3,
    EXIT_STORAGE    => 4,
    EXIT_INTERNAL   => 5,
};

sub run {
    my ($class, @argv) = @_;

    return _usage(*STDERR, EXIT_USAGE) if @argv == 0;
    return _usage(*STDOUT, EXIT_SUCCESS) if @argv == 1 && ($argv[0] eq '--help' || $argv[0] eq 'help');

    my $command = shift @argv;

    if ($command eq 'create-game') {
        return _run_checked_command($command, \@argv, \&_command_create_game);
    }

    if ($command eq 'verify') {
        return _run_checked_command($command, \@argv, \&_command_verify);
    }

    if ($command eq 'replay') {
        return _run_checked_command($command, \@argv, \&_command_replay);
    }

    if ($command eq 'project') {
        return _run_checked_command($command, \@argv, \&_command_project);
    }

    if ($command eq 'sgf') {
        return _run_checked_command($command, \@argv, \&_command_sgf);
    }

    if ($command eq 'publish-move') {
        return _run_checked_command($command, \@argv, \&_command_publish_move);
    }

    if ($command eq 'publish-ack') {
        return _run_checked_command($command, \@argv, \&_command_publish_ack);
    }

    if ($command eq 'play') {
        return _run_checked_command($command, \@argv, \&_command_play);
    }

    if ($command eq 'watch') {
        return _run_checked_command($command, \@argv, \&_command_watch);
    }

    print STDERR "unknown command: $command\n";
    return _usage(*STDERR, EXIT_USAGE);
}

sub _run_checked_command {
    my ($command, $argv, $code) = @_;

    my $exit = eval { $code->(@$argv) };
    if (defined $exit) {
        return $exit;
    }

    my $error = $@ || 'unknown error';
    chomp $error;
    $error = redact_text(_clean_error($error));

    if ($error =~ /\Ausage:/) {
        print STDERR "$error\n";
        return _usage(*STDERR, EXIT_USAGE);
    }

    if ($error =~ /\Astorage:/) {
        $error =~ s/\Astorage:\s*//;
        print STDERR "storage: $error\n";
        return EXIT_STORAGE;
    }

    print STDERR "internal: $error\n";
    return EXIT_INTERNAL;
}

sub _command_create_game {
    my (@argv) = @_;

    my ($descriptor, $error) = _descriptor_from_create_args(@argv);
    die "usage: create-game [--id id --black player --white player] [--size n] [--rules id] [--komi milli]\n"
        if defined $error;

    my $context = eval { context_for_descriptor($descriptor) };
    die 'storage: ' . $@ if !$context;

    eval {
        $context->{store}->mkdir($context->{store_game_root});
        $context->{store}->mkdir("$context->{store_game_root}/events");
        $context->{store}->mkdir("$context->{store_game_root}/tmp");
        1;
    } or die 'storage: ' . $@;

    print STDOUT "gobanftp.create-game=ok\n";
    print STDOUT "store=$context->{store_kind}\n";
    print STDOUT "game=$context->{game_descriptor}\n";
    print STDOUT "root=$context->{game_root}\n";

    return EXIT_SUCCESS;
}

sub _command_verify {
    my (@argv) = @_;
    die "usage: verify <game-root|game-descriptor>" if @argv != 1;

    my $context = _load_context($argv[0]);
    my $exit    = _result_exit($context->{replay_result});
    my $status  = $exit == EXIT_SUCCESS ? 'ok' : $exit == EXIT_CONFLICT ? 'fork' : 'failed';

    _print_summary('verify', $status, $context);
    _print_diagnostics($context->{replay_result});

    return $exit;
}

sub _command_replay {
    my (@argv) = @_;
    die "usage: replay <game-root|game-descriptor>" if @argv != 1;

    my $context = _load_context($argv[0]);
    my $exit    = _result_exit($context->{replay_result});
    my $status  = $exit == EXIT_SUCCESS ? 'ok' : $exit == EXIT_CONFLICT ? 'fork' : 'failed';

    _print_summary('replay', $status, $context);
    print STDOUT 'canonical_ids=' . join(',', _canonical_ids($context->{replay_result})) . "\n";
    _print_diagnostics($context->{replay_result});

    return $exit;
}

sub _command_project {
    my (@argv) = @_;
    die "usage: project <game-root|game-descriptor>" if @argv != 1;

    _require_local_store_for_write('project writes local projection files and requires the local store');

    my $context = eval { context_for_game_arg($argv[0]) };
    die 'storage: ' . $@ if !$context;

    $context = _reload_context($context);
    my $exit    = _result_exit($context->{replay_result});
    if ($exit != EXIT_SUCCESS && ($exit != EXIT_CONFLICT || $context->{store_kind} ne 'local')) {
        _print_summary('project', $exit == EXIT_CONFLICT ? 'fork' : 'failed', $context);
        _print_diagnostics($context->{replay_result});
        return $exit;
    }

    my $written = write_projection(
        game_root       => $context->{game_root},
        game_descriptor => $context->{game_descriptor},
        events          => $context->{events},
        replay_result   => $context->{replay_result},
    );

    _print_summary('project', $exit == EXIT_CONFLICT ? 'fork' : 'ok', $context);
    print STDOUT "sgf=$written->{paths}{sgf}\n";
    print STDOUT "board=$written->{paths}{board}\n";
    print STDOUT "verdict=$written->{paths}{verdict}\n";
    print STDOUT "listing=$written->{paths}{listing}\n";
    _print_diagnostics($context->{replay_result});

    return $exit;
}

sub _command_sgf {
    my (@argv) = @_;

    my $write = 0;
    my $variations = 0;
    @argv = grep {
        if ($_ eq '--write') {
            $write = 1;
            0;
        }
        elsif ($_ eq '--variations') {
            $variations = 1;
            0;
        }
        else {
            1;
        }
    } @argv;
    die "usage: sgf [--write] <game-root|game-descriptor> | sgf --variations <game-root|game-descriptor>"
        if @argv != 1 || ($write && $variations);

    my $context;
    if ($write) {
        _require_local_store_for_write('sgf --write writes local projection files and requires the local store');

        $context = eval { context_for_game_arg($argv[0]) };
        die 'storage: ' . $@ if !$context;
        $context = _reload_context($context);
    }
    else {
        $context = _load_context($argv[0]);
    }

    my $exit    = _result_exit($context->{replay_result});
    if ($exit != EXIT_SUCCESS) {
        if ($variations && $exit == EXIT_CONFLICT) {
            my $rendered = render_projection(
                game_descriptor => $context->{game_descriptor},
                events          => $context->{events},
                replay_result   => $context->{replay_result},
            );
            print STDOUT $rendered->{sgf_variations};
            _print_diagnostics($context->{replay_result});
            return $exit;
        }

        _print_summary('sgf', $exit == EXIT_CONFLICT ? 'fork' : 'failed', $context);
        _print_diagnostics($context->{replay_result});
        return $exit;
    }

    if ($write) {
        my $written = write_sgf_projection(
            game_root       => $context->{game_root},
            game_descriptor => $context->{game_descriptor},
            events          => $context->{events},
            replay_result   => $context->{replay_result},
        );
        print STDOUT "gobanftp.sgf=ok\n";
        print STDOUT "game=$context->{game_descriptor}\n";
        print STDOUT "sgf=$written->{path}\n";
        return EXIT_SUCCESS;
    }

    my $rendered = render_projection(
        game_descriptor => $context->{game_descriptor},
        events          => $context->{events},
        replay_result   => $context->{replay_result},
    );
    print STDOUT $variations ? $rendered->{sgf_variations} : $rendered->{sgf};

    return EXIT_SUCCESS;
}

sub _command_publish_move {
    my (@argv) = @_;

    my %opts;
    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--nonce') {
            die "usage: publish-move [--nonce n] <game-root|game-descriptor> <aa|play-aa|pass|resign>"
                if !@argv;
            $opts{nonce} = shift @argv;
            next;
        }
        if ($option =~ /\A--nonce=(.+)\z/) {
            $opts{nonce} = $1;
            next;
        }
        die "usage: publish-move [--nonce n] <game-root|game-descriptor> <aa|play-aa|pass|resign>";
    }

    die "usage: publish-move [--nonce n] <game-root|game-descriptor> <aa|play-aa|pass|resign>"
        if @argv != 2;
    die "usage: publish-move [--nonce n] <game-root|game-descriptor> <aa|play-aa|pass|resign>"
        if defined($opts{nonce}) && $opts{nonce} !~ /\A[a-z0-9_-]{1,16}\z/;

    my ($game_arg, $move_input) = @argv;
    my ($action, $action_error) = normalize_action($move_input);
    die "usage: publish-move [--nonce n] <game-root|game-descriptor> <aa|play-aa|pass|resign>"
        if defined $action_error;

    my $context = _load_context($game_arg);
    return _publish_action(
        command => 'publish-move',
        context => $context,
        action  => $action,
        defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
    );
}

sub _command_publish_ack {
    my (@argv) = @_;

    my %opts;
    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--nonce') {
            die "usage: publish-ack [--nonce n] <game-root|game-descriptor> <event-id>"
                if !@argv;
            $opts{nonce} = shift @argv;
            next;
        }
        if ($option =~ /\A--nonce=(.+)\z/) {
            $opts{nonce} = $1;
            next;
        }
        die "usage: publish-ack [--nonce n] <game-root|game-descriptor> <event-id>";
    }

    die "usage: publish-ack [--nonce n] <game-root|game-descriptor> <event-id>"
        if @argv != 2;
    die "usage: publish-ack [--nonce n] <game-root|game-descriptor> <event-id>"
        if defined($opts{nonce}) && $opts{nonce} !~ /\A[a-z0-9_-]{1,16}\z/;

    my ($game_arg, $target_id) = @argv;
    die "usage: publish-ack [--nonce n] <game-root|game-descriptor> <event-id>"
        if $target_id !~ /\A[0-9a-v]{16}\z/;

    my $context = _load_context($game_arg);
    return _publish_ack(
        command   => 'publish-ack',
        context   => $context,
        target_id => $target_id,
        defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
    );
}

sub _command_play {
    my (@argv) = @_;
    my $usage = "usage: play [--once] [--move move|--ack event-id] [--nonce n] <game-root|game-descriptor>";

    my %opts;
    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--once') {
            $opts{once} = 1;
            next;
        }
        if ($option eq '--move') {
            die $usage
                if !@argv;
            $opts{move} = shift @argv;
            next;
        }
        if ($option =~ /\A--move=(.+)\z/) {
            $opts{move} = $1;
            next;
        }
        if ($option eq '--ack') {
            die $usage
                if !@argv;
            $opts{ack} = shift @argv;
            next;
        }
        if ($option =~ /\A--ack=(.+)\z/) {
            $opts{ack} = $1;
            next;
        }
        if ($option eq '--nonce') {
            die $usage
                if !@argv;
            $opts{nonce} = shift @argv;
            next;
        }
        if ($option =~ /\A--nonce=(.+)\z/) {
            $opts{nonce} = $1;
            next;
        }
        die $usage;
    }

    die $usage if @argv != 1 || (defined($opts{move}) && defined($opts{ack}));
    die $usage
        if defined($opts{nonce}) && $opts{nonce} !~ /\A[a-z0-9_-]{1,16}\z/;
    die $usage
        if defined($opts{ack}) && $opts{ack} !~ /\A[0-9a-v]{16}\z/;

    my ($game_arg) = @argv;

    if (defined $opts{move}) {
        my ($action, $action_error) = normalize_action($opts{move});
        die $usage if defined $action_error;

        my $context = _load_context($game_arg);
        my $publish = _publish_action_result(
            command => 'play',
            context => $context,
            action  => $action,
            defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
        );
        if ($publish->{exit} != EXIT_SUCCESS) {
            if ($publish->{stage} eq 'published') {
                _print_event_result($publish);
                my $exit = _print_terminal_snapshot('play', $publish->{context});
                _print_diagnostics($publish->{context}{replay_result});
                return $exit;
            }

            _print_publish_result('play', $publish);
            return $publish->{exit};
        }

        _print_event_result($publish);
        return _print_terminal_snapshot('play', $publish->{context});
    }

    if (defined $opts{ack}) {
        my $context = _load_context($game_arg);
        my $publish = _publish_ack_result(
            command       => 'play',
            context       => $context,
            target_id     => $opts{ack},
            reload_policy => 'ack-assisted',
            defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
        );
        if ($publish->{stage} ne 'published') {
            _print_publish_result('play', $publish);
            return $publish->{exit};
        }

        _print_event_result($publish);
        my $exit = _print_terminal_snapshot('play', $publish->{context});
        _print_diagnostics($publish->{context}{replay_result});
        return $exit;
    }

    my $context = _load_context($game_arg);
    my $exit = _print_terminal_snapshot('play', $context);
    _print_diagnostics($context->{replay_result});
    return $exit if $opts{once} || $exit != EXIT_SUCCESS || _terminal_replay($context->{replay_result});

    while (1) {
        print STDERR "move> ";
        my $line = <STDIN>;
        return EXIT_SUCCESS if !defined $line;

        chomp $line;
        $line =~ s/\A\s+//;
        $line =~ s/\s+\z//;
        next if $line eq '';
        return EXIT_SUCCESS if $line eq 'quit' || $line eq 'exit' || $line eq 'q';

        if ($line eq 'refresh') {
            $context = _load_context($game_arg);
            $exit = _print_terminal_snapshot('play', $context);
            _print_diagnostics($context->{replay_result});
            return $exit if $exit != EXIT_SUCCESS || _terminal_replay($context->{replay_result});
            next;
        }

        my ($action, $action_error) = normalize_action($line);
        if (defined $action_error) {
            print STDERR "usage: enter aa, play-aa, pass, resign, refresh, quit, exit, or q\n";
            next;
        }

        my $move_context = _load_context($game_arg);
        my $publish = _publish_action_result(
            command => 'play',
            context => $move_context,
            action  => $action,
        );
        if ($publish->{exit} != EXIT_SUCCESS) {
            if ($publish->{stage} eq 'published') {
                _print_event_result($publish);
                $context = $publish->{context};
                $exit = _print_terminal_snapshot('play', $context);
                _print_diagnostics($context->{replay_result});
                return $exit;
            }

            _print_publish_result('play', $publish);
            next if $publish->{stage} eq 'candidate' && $publish->{exit} == EXIT_VALIDATION;
            return $publish->{exit};
        }

        _print_event_result($publish);
        $context = $publish->{context};
        $exit = _print_terminal_snapshot('play', $context);
        _print_diagnostics($context->{replay_result});
        return $exit if $exit != EXIT_SUCCESS || _terminal_replay($context->{replay_result});
    }
}

sub _command_watch {
    my (@argv) = @_;

    my %opts = (
        interval => 2,
    );

    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--once') {
            $opts{count} = 1;
            next;
        }
        if ($option eq '--count') {
            die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>"
                if !@argv;
            $opts{count} = shift @argv;
            next;
        }
        if ($option =~ /\A--count=(.+)\z/) {
            $opts{count} = $1;
            next;
        }
        if ($option eq '--max-polls') {
            die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>"
                if !@argv;
            $opts{count} = shift @argv;
            next;
        }
        if ($option =~ /\A--max-polls=(.+)\z/) {
            $opts{count} = $1;
            next;
        }
        if ($option eq '--interval') {
            die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>"
                if !@argv;
            $opts{interval} = shift @argv;
            next;
        }
        if ($option =~ /\A--interval=(.+)\z/) {
            $opts{interval} = $1;
            next;
        }
        die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>";
    }

    die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>"
        if @argv != 1;
    die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>"
        if defined($opts{count}) && $opts{count} !~ /\A[1-9][0-9]*\z/;
    die "usage: watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>"
        if !defined($opts{interval}) || $opts{interval} !~ /\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/;

    my ($game_arg) = @argv;
    my $snapshot = 0;

    while (!defined($opts{count}) || $snapshot < $opts{count}) {
        $snapshot++;

        my $context = _load_context($game_arg);
        my $exit = _print_terminal_snapshot('watch', $context, snapshot => $snapshot);
        _print_diagnostics($context->{replay_result});
        return $exit if $exit != EXIT_SUCCESS;

        last if defined($opts{count}) && $snapshot >= $opts{count};
        select undef, undef, undef, 0 + $opts{interval};
    }

    return EXIT_SUCCESS;
}

sub _publish_action {
    my (%args) = @_;

    my $result = _publish_action_result(%args);
    _print_publish_result($args{command} // 'publish-move', $result);

    return $result->{exit};
}

sub _publish_ack {
    my (%args) = @_;

    my $result = _publish_ack_result(%args);
    _print_publish_result($args{command} // 'publish-ack', $result);

    return $result->{exit};
}

sub _publish_action_result {
    my (%args) = @_;

    my $context = $args{context};
    my $action  = $args{action};

    my $pre_exit = _result_exit($context->{replay_result});
    if ($pre_exit != EXIT_SUCCESS) {
        return {
            exit    => $pre_exit,
            stage   => 'preexisting',
            context => $context,
        };
    }

    my ($event_name, $event_id) = build_next_move_name(
        game_descriptor => $context->{game_descriptor},
        replay_result   => $context->{replay_result},
        action          => $action,
        defined($args{nonce}) ? (nonce => $args{nonce}) : (),
    );

    my @validation_events = sort_event_basenames(@{ $context->{events} }, $event_name);
    my $validation_result = replay(
        game_descriptor => $context->{game_descriptor},
        events          => \@validation_events,
    );
    my $validation_exit = _result_exit($validation_result);
    if ($validation_exit != EXIT_SUCCESS) {
        my $validation_context = {
            %$context,
            events        => \@validation_events,
            replay_result => $validation_result,
        };
        return {
            exit       => $validation_exit,
            stage      => 'candidate',
            context    => $validation_context,
            event_name => $event_name,
            event_id   => $event_id,
        };
    }

    eval {
        $context->{store}->publish_event_name($context->{store_game_root}, $event_name);
        1;
    } or die 'storage: ' . $@;

    my $after_context = _reload_context($context);
    my $after_exit = _result_exit($after_context->{replay_result});

    return {
        exit       => $after_exit,
        stage      => 'published',
        context    => $after_context,
        event_name => $event_name,
        event_id   => $event_id,
    };
}

sub _publish_ack_result {
    my (%args) = @_;

    my $context   = $args{context};
    my $target_id = $args{target_id};

    my $pre_exit = _result_exit($context->{replay_result});
    if ($pre_exit == EXIT_VALIDATION) {
        return {
            exit    => $pre_exit,
            stage   => 'preexisting',
            context => $context,
        };
    }

    my ($event_name, $event_id) = eval {
        build_ack_for_target(
            game_descriptor => $context->{game_descriptor},
            replay_result   => $context->{replay_result},
            target_id       => $target_id,
            defined($args{nonce}) ? (nonce => $args{nonce}) : (),
        );
    };
    if ($@) {
        my $diagnostic = _ack_target_diagnostic($target_id, $@);
        return {
            exit    => EXIT_VALIDATION,
            stage   => 'candidate',
            context => {
                %$context,
                replay_result => _result_with_diagnostic($context->{replay_result}, $diagnostic),
            },
        };
    }

    my @validation_events = sort_event_basenames(@{ $context->{events} }, $event_name);
    my $validation_result = replay(
        game_descriptor => $context->{game_descriptor},
        events          => \@validation_events,
    );
    my $validation_exit = _result_exit($validation_result);
    if ($validation_exit == EXIT_VALIDATION) {
        my $validation_context = {
            %$context,
            events        => \@validation_events,
            replay_result => $validation_result,
        };
        return {
            exit       => $validation_exit,
            stage      => 'candidate',
            context    => $validation_context,
            event_name => $event_name,
            event_id   => $event_id,
        };
    }

    eval {
        $context->{store}->publish_event_name($context->{store_game_root}, $event_name);
        1;
    } or die 'storage: ' . $@;

    my $after_context = _reload_context(
        $context,
        policy => $args{reload_policy} // 'conservative',
    );
    my $after_exit = _result_exit($after_context->{replay_result});

    return {
        exit       => $after_exit,
        stage      => 'published',
        context    => $after_context,
        event_name => $event_name,
        event_id   => $event_id,
    };
}

sub _print_publish_result {
    my ($command, $result) = @_;

    _print_summary($command, _status_for_exit($result->{exit}), $result->{context});
    _print_event_result($result);
    _print_diagnostics($result->{context}{replay_result});
}

sub _print_event_result {
    my ($result) = @_;

    print STDOUT "event=$result->{event_name}\n" if defined $result->{event_name};
    print STDOUT "event_id=$result->{event_id}\n" if defined $result->{event_id};
}

sub _load_context {
    my ($game_root_arg, %opts) = @_;

    my $context = eval { context_for_game_arg($game_root_arg) };
    die 'storage: ' . $@ if !$context;

    return _reload_context($context, %opts);
}

sub _reload_context {
    my ($context, %opts) = @_;

    my @events = eval { normalize_listing($context->{store}->list_names("$context->{store_game_root}/events")) };
    die 'storage: ' . $@ if $@;

    my $result = replay(
        game_descriptor => $context->{game_descriptor},
        events          => \@events,
        defined($opts{policy}) ? (policy => $opts{policy}) : (),
    );

    return {
        %$context,
        events        => \@events,
        replay_result => $result,
    };
}

sub _ack_target_diagnostic {
    my ($target_id, $error) = @_;

    chomp $error;
    $error = _clean_error($error);

    my $reason = $error eq 'ack.target'       ? 'unknown'
        : $error eq 'ack.target_move'        ? 'not_move'
        : $error eq 'ack.target_legal'       ? 'not_legal'
        :                                      'invalid';

    return {
        code      => 'ack_target_invalid',
        target_id => $target_id,
        reason    => $reason,
        error     => $error,
    };
}

sub _result_with_diagnostic {
    my ($result, $diagnostic) = @_;

    return {
        policy                   => ref($result) && eval { $result->can('policy') } ? $result->policy : 'conservative',
        diagnostics              => [ _diagnostics($result), $diagnostic ],
        canonical_ids            => [ _canonical_ids($result) ],
        legal_ids                => [ _legal_ids($result) ],
        illegal_by_id            => ref($result) && eval { $result->can('illegal_by_id') } ? $result->illegal_by_id : {},
        fork                     => _fork($result),
        final_state              => _final_state($result),
        game                     => _game($result),
        events_by_id             => ref($result) && eval { $result->can('events_by_id') } ? $result->events_by_id : {},
        names_by_id              => ref($result) && eval { $result->can('names_by_id') } ? $result->names_by_id : {},
        canonical_steps          => ref($result) && eval { $result->can('canonical_steps') } ? [ $result->canonical_steps ] : [],
        legal_children_by_parent => ref($result) && eval { $result->can('legal_children_by_parent') } ? $result->legal_children_by_parent : {},
        ack_ids_by_target        => ref($result) && eval { $result->can('ack_ids_by_target') } ? $result->ack_ids_by_target : {},
        ack_assisted_choices     => ref($result) && eval { $result->can('ack_assisted_choices') } ? [ $result->ack_assisted_choices ] : [],
    };
}

sub _require_local_store_for_write {
    my ($message) = @_;

    my $mode = eval { store_mode() };
    die 'storage: ' . $@ if !$mode;
    die "storage: $message" if $mode ne 'local';

    return 1;
}

sub _descriptor_from_create_args {
    my (@argv) = @_;

    if (@argv == 1) {
        my ($fields, $error) = parse_basename($argv[0]);
        return ($argv[0], undef) if !defined $error;
        return (undef, $error);
    }

    my %opts = (
        size  => 19,
        rules => 'chinese-area-v1',
        komi  => 7500,
    );

    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        my ($name, $value);

        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        else {
            $name = substr($option, 2);
            return (undef, 'option.value') if !@argv;
            $value = shift @argv;
        }

        return (undef, 'option.name')
            if $name !~ /\A(?:id|size|rules|komi|black|white)\z/;

        $opts{ $name eq 'id' ? 'game_id' : $name } = $value;
    }

    if (@argv == 3 && !defined($opts{game_id}) && !defined($opts{black}) && !defined($opts{white})) {
        @opts{qw(game_id black white)} = @argv;
        @argv = ();
    }

    return (undef, 'argument.count') if @argv;

    my $descriptor = eval {
        build_basename(
            game_id => $opts{game_id},
            size    => $opts{size},
            rules   => $opts{rules},
            komi    => $opts{komi},
            black   => $opts{black},
            white   => $opts{white},
        );
    };
    return ($descriptor, undef) if defined $descriptor;

    my $error = $@ || 'gamespec';
    chomp $error;
    return (undef, _clean_error($error));
}

sub _print_summary {
    my ($command, $status, $context) = @_;

    my $result = $context->{replay_result};
    print STDOUT "gobanftp.$command=$status\n";
    print STDOUT "game=$context->{game_descriptor}\n";
    print STDOUT 'events=' . scalar(@{ $context->{events} }) . "\n";
    print STDOUT 'canonical_moves=' . scalar(_canonical_ids($result)) . "\n";
    print STDOUT 'legal_moves=' . scalar(_legal_ids($result)) . "\n";
}

sub _print_diagnostics {
    my ($result) = @_;

    for my $diagnostic (_diagnostics($result)) {
        print STDERR redact_text(_diagnostic_line($diagnostic)), "\n";
    }
}

sub _print_terminal_snapshot {
    my ($command, $context, %opts) = @_;

    my $result = $context->{replay_result};
    my $exit   = _result_exit($result);
    my $status = $exit == EXIT_SUCCESS ? 'ok' : $exit == EXIT_CONFLICT ? 'fork' : 'failed';

    _print_summary($command, $status, $context);
    print STDOUT "snapshot=$opts{snapshot}\n" if defined $opts{snapshot};
    _print_turn($result);
    _print_worldline($result);

    my $rendered = render_projection(
        game_descriptor => $context->{game_descriptor},
        events          => $context->{events},
        replay_result   => $result,
    );
    print STDOUT $rendered->{board};

    return $exit;
}

sub _print_turn {
    my ($result) = @_;

    my $state = _final_state($result);
    my $game  = _game($result);
    my $color = ref($state) eq 'HASH' ? ($state->{next_color} // '') : '';

    print STDOUT "turn_color=$color\n";
    if (ref($game) eq 'HASH') {
        my $player = $color eq 'b' ? $game->{black}
            : $color eq 'w'        ? $game->{white}
            :                        undef;
        print STDOUT "turn_player=$player\n" if defined $player;
    }
}

sub _print_worldline {
    my ($result) = @_;

    my @diagnostics = _diagnostics($result);
    my $fork = _fork($result) // _fork_diagnostic(@diagnostics);
    my $has_validation = grep { ($_->{code} // '') ne 'fork' } @diagnostics;
    my $status = $has_validation ? 'validation' : defined($fork) ? 'fork' : 'main';

    print STDOUT "worldline.status=$status\n";
    print STDOUT 'worldline.canonical_ids=' . join(',', _canonical_ids($result)) . "\n";
    print STDOUT 'worldline.legal_ids=' . join(',', _legal_ids($result)) . "\n";

    if (defined $fork) {
        print STDOUT 'worldline.fork.parent_id=' . ($fork->{parent_id} // '') . "\n";
        print STDOUT 'worldline.fork.child_ids=' . join(',', @{ $fork->{child_ids} // [] }) . "\n";
    }
}

sub _diagnostic_line {
    my ($diagnostic) = @_;

    my @fields = ('diagnostic');
    for my $key (sort keys %$diagnostic) {
        my $value = $diagnostic->{$key};
        if (ref($value) eq 'ARRAY') {
            $value = join(',', @$value);
        }
        elsif (ref($value)) {
            next;
        }
        push @fields, "$key=$value";
    }

    return join(' ', @fields);
}

sub _result_exit {
    my ($result) = @_;

    my @diagnostics = _diagnostics($result);
    return EXIT_SUCCESS if !@diagnostics;
    return EXIT_VALIDATION if grep { ($_->{code} // '') ne 'fork' } @diagnostics;
    return EXIT_CONFLICT;
}

sub _status_for_exit {
    my ($exit) = @_;
    return $exit == EXIT_SUCCESS  ? 'ok'
        : $exit == EXIT_CONFLICT ? 'fork'
        :                          'failed';
}

sub _canonical_ids {
    my ($result) = @_;
    return $result->canonical_ids if ref($result) && eval { $result->can('canonical_ids') };
    return @{ $result->{canonical_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _legal_ids {
    my ($result) = @_;
    return $result->legal_ids if ref($result) && eval { $result->can('legal_ids') };
    return @{ $result->{legal_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _diagnostics {
    my ($result) = @_;
    return $result->diagnostics if ref($result) && eval { $result->can('diagnostics') };
    return @{ $result->{diagnostics} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _final_state {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->final_state if eval { $result->can('final_state') };
    return $result->{final_state} if (reftype($result) // '') eq 'HASH';
    return undef;
}

sub _fork {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->fork if eval { $result->can('fork') };
    return $result->{fork} if (reftype($result) // '') eq 'HASH';
    return undef;
}

sub _game {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->game if eval { $result->can('game') };
    return $result->{game} if (reftype($result) // '') eq 'HASH';
    return undef;
}

sub _terminal_replay {
    my ($result) = @_;
    my $state = _final_state($result);
    return ref($state) eq 'HASH' && $state->{terminal} ? 1 : 0;
}

sub _fork_diagnostic {
    for my $diagnostic (@_) {
        return $diagnostic if ($diagnostic->{code} // '') eq 'fork';
    }
    return undef;
}

sub _usage {
    my ($fh, $status) = @_;

    print {$fh} <<'USAGE';
usage: gobanftp <command> <game-root>

commands:
  create-game <game-descriptor>
  create-game --id id --black player --white player [--size n] [--rules id] [--komi milli]
  verify <game-root|game-descriptor>
  replay <game-root|game-descriptor>
  sgf [--write] <game-root|game-descriptor>
  sgf --variations <game-root|game-descriptor>
  project <game-root|game-descriptor>
  publish-move [--nonce n] <game-root|game-descriptor> <aa|play-aa|pass|resign>
  publish-ack [--nonce n] <game-root|game-descriptor> <event-id>
  play [--once] [--move move|--ack event-id] [--nonce n] <game-root|game-descriptor>
  watch [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>
USAGE

    return $status;
}

sub _clean_error {
    my ($error) = @_;

    $error =~ s/\s+at \S+ line [0-9]+\.?\z//;
    return $error;
}

1;

__END__

=head1 NAME

GobanFTP::CLI - local GobanFTP command entry points

=cut
