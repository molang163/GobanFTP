use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

my $root = "$FindBin::Bin/..";

my $make = _slurp("$root/Makefile.PL");
my $cpan = _slurp("$root/cpanfile");
my $build = _slurp("$root/docs/BUILD.md");

my $make_perl = _make_min_perl($make);
my ($cpan_perl, $cpan_runtime, $cpan_test, $cpan_optional) = _cpanfile_modules($cpan);
my $docs = _build_dependency_block($build);

my $make_runtime = _make_hash_modules($make, 'PREREQ_PM');
my $make_test = _make_hash_modules($make, 'TEST_REQUIRES');
my $make_optional = _make_recommends($make);

is $make_perl, $cpan_perl, 'Makefile.PL and cpanfile minimum Perl versions match';
is_deeply [ _docs_perl_parts($build) ], [ _perl_version_parts($make_perl) ],
    'docs/BUILD documents the same minimum Perl target';

is_deeply [sort keys %$make_runtime], [sort keys %$cpan_runtime],
    'Makefile.PL and cpanfile runtime dependencies match';
is_deeply [sort keys %$make_test], [sort keys %$cpan_test],
    'Makefile.PL and cpanfile test dependencies match';
is_deeply [sort keys %$make_optional], [sort keys %$cpan_optional],
    'Makefile.PL and cpanfile optional dependencies match';

is_deeply $make_runtime, $cpan_runtime, 'runtime dependency version constraints match';
is_deeply $make_test, $cpan_test, 'test dependency version constraints match';
is_deeply $make_optional, $cpan_optional, 'optional dependency version constraints match';

is_deeply $docs->{runtime}, [sort keys %$cpan_runtime],
    'docs/BUILD runtime dependency list matches cpanfile';
is_deeply $docs->{test}, [sort keys %$cpan_test],
    'docs/BUILD test dependency list matches cpanfile';
is_deeply $docs->{optional}, [sort keys %$cpan_optional],
    'docs/BUILD optional dependency list matches cpanfile';

done_testing;

sub _make_hash_modules {
    my ($text, $label) = @_;

    my ($body) = $text =~ /\Q$label\E\s*=>\s*\{(.*?)\n\s*\}/s;
    die "missing $label in Makefile.PL" if !defined $body;

    return +{ map { $_->[0] => $_->[1] } _make_pairs($body) };
}

sub _make_recommends {
    my ($text) = @_;

    my ($body) = $text =~ /recommends\s*=>\s*\{(.*?)\n\s*\}/s;
    return +{} if !defined $body;

    return +{ map { $_->[0] => $_->[1] } _make_pairs($body) };
}

sub _cpanfile_modules {
    my ($text) = @_;

    my (%runtime, %test, %optional);
    my $perl;
    my $in_test = 0;

    for my $line (split /\n/, $text) {
        $in_test = 1 if $line =~ /\Aon\s+'test'\s+=>\s+sub\s+\{/;
        if ($line =~ /\A\s*requires\s+'([^']+)'(?:\s*,\s*'([^']+)')?/) {
            my ($module, $version) = ($1, _version($2));
            if ($module eq 'perl') {
                $perl = $version;
                next;
            }
            if ($in_test) {
                $test{$module} = $version;
            }
            else {
                $runtime{$module} = $version;
            }
        }
        elsif ($line =~ /\A\s*recommends\s+'([^']+)'(?:\s*,\s*'([^']+)')?/) {
            $optional{$1} = _version($2);
        }
        $in_test = 0 if $in_test && $line =~ /\A\};/;
    }

    die 'missing perl requirement in cpanfile' if !defined $perl;
    return ($perl, \%runtime, \%test, \%optional);
}

sub _make_min_perl {
    my ($text) = @_;

    my ($version) = $text =~ /MIN_PERL_VERSION\s*=>\s*'([^']+)'/;
    die 'missing MIN_PERL_VERSION in Makefile.PL' if !defined $version;
    return _version($version);
}

sub _make_pairs {
    my ($body) = @_;

    my @pairs;
    while ($body =~ /'([^']+)'\s*=>\s*([^,\n]+)/g) {
        push @pairs, [ $1, _version($2) ];
    }
    return @pairs;
}

sub _version {
    my ($version) = @_;
    $version //= 0;
    $version =~ s/\A\s+|\s+\z//g;
    $version =~ s/\A['"]|['"]\z//g;
    return "$version";
}

sub _perl_version_parts {
    my ($version) = @_;
    my ($major, $minor) = $version =~ /\A([0-9]+)\.0*([0-9]+)\z/;
    die "bad Perl version: $version" if !defined $major;
    return (0 + $major, 0 + $minor);
}

sub _docs_perl_parts {
    my ($text) = @_;
    my ($major, $minor) = $text =~ /\bPerl\s+([0-9]+)\.([0-9]+)\+/;
    die 'missing minimum Perl version in docs/BUILD.md' if !defined $major;
    return (0 + $major, 0 + $minor);
}

sub _build_dependency_block {
    my ($text) = @_;

    my ($body) = $text =~ /<!-- gobanftp-deps:start -->\s*```text\n(.*?)```\s*<!-- gobanftp-deps:end -->/s;
    die 'missing gobanftp dependency block in docs/BUILD.md' if !defined $body;

    my %deps;
    for my $line (split /\n/, $body) {
        next if $line =~ /\A\s*\z/;
        my ($kind, $modules) = $line =~ /\A(runtime|test|optional):\s*(.*?)\s*\z/;
        die "bad dependency line: $line" if !defined $kind;
        $deps{$kind} = [ sort grep { length } split /\s+/, $modules ];
    }

    for my $kind (qw(runtime test optional)) {
        die "missing $kind dependency line" if !exists $deps{$kind};
    }

    return \%deps;
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text;
}
