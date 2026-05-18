use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Profile::Adapter qw(profile_listing_names);

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my @events = qw(
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
);

subtest 'local and FTP profiles expose raw listing names unchanged' => sub {
    my @raw = (
        "events/$events[0]",
        'tmp/pending.part',
        $events[1],
    );

    for my $profile (qw(local-goftp1 ftp-goftp1)) {
        is_deeply [
            profile_listing_names(
                profile_id      => $profile,
                game_descriptor => $game,
                raw_names       => \@raw,
            )
        ], \@raw, "$profile uses listing identity";
    }
};

subtest 'git tree adapter extracts only visible tree paths' => sub {
    my @raw = (
        "100644 blob aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tevents/$events[0]",
        "100755 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb blob events/$events[1]",
        "mode=100644 object=cccccccccccccccccccccccccccccccccccccccc type=blob path=$game/events/$events[0]",
        "mode=100644 object=dddddddddddddddddddddddddddddddddddddddd type=blob path=README",
        './tmp/pending.part',
        'not a tree row',
    );

    is_deeply [
        profile_listing_names(
            profile_id      => 'git-tree-goftp1',
            game_descriptor => $game,
            raw_names       => \@raw,
        )
    ], [
        "events/$events[0]",
        "events/$events[1]",
        "events/$events[0]",
        'README',
        'tmp/pending.part',
    ], 'git tree normalizer strips git metadata and game prefix';
};

subtest 'DNS record adapter extracts lower-case TXT event values' => sub {
    my @raw = (
        "ttl=60 type=txt event=\"$events[0]\"",
        "owner=_goban type=TXT event=$events[1]",
        "ttl=60 type=a event=$events[0]",
        'type=txt note=ignored',
        "type=txt event=\"../$events[0]\"",
    );

    is_deeply [
        profile_listing_names(
            profile_id      => 'dns-record-goftp1',
            game_descriptor => $game,
            raw_names       => \@raw,
        )
    ], [
        $events[0],
        $events[1],
    ], 'DNS TXT normalizer extracts event= values and ignores non-events';
};

subtest 'WebDAV adapter extracts direct events hrefs and decodes once' => sub {
    my @raw = (
        "<href>https://dav.example/$game/events/$events[0]</href>",
        qq{<D:response href="/$game/events/$events[1]?etag=ignored" />},
        qq{href='/events/$events[0]'},
        qq{href=/events/not%2fan-event},
        qq{href=/events/bad%zz},
        qq{href=/events/$events[0]/child},
        qq{href=/tmp/$events[0]},
    );

    is_deeply [
        profile_listing_names(
            profile_id      => 'webdav-goftp1',
            game_descriptor => $game,
            raw_names       => \@raw,
        )
    ], [
        "events/$events[0]",
        "events/$events[1]",
        "events/$events[0]",
    ], 'WebDAV normalizer keeps direct event hrefs only';
};

like dies(sub {
    profile_listing_names(
        profile_id      => 'no-such-profile',
        game_descriptor => $game,
        raw_names       => [],
    );
}), qr/unknown profile_id/, 'unknown profile is rejected';

done_testing;

sub dies {
    my ($code) = @_;
    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    return $error;
}
