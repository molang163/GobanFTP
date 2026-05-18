package GobanFTP::Profile::Adapter;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

use GobanFTP::Profile qw(profile);

our @EXPORT_OK = qw(profile_listing_names);

sub profile_listing_names {
    my %args = _args(@_);

    my $profile_id = _required($args{profile_id}, 'profile_id');
    my $game       = _required($args{game_descriptor}, 'game_descriptor');
    my $raw_names  = _array_ref($args{raw_names} // $args{names} // [], 'raw_names');

    profile($profile_id);

    return _git_tree_listing_names($game, $raw_names) if $profile_id eq 'git-tree-goftp1';
    return _dns_record_listing_names($game, $raw_names) if $profile_id eq 'dns-record-goftp1';
    return _webdav_listing_names($game, $raw_names)   if $profile_id eq 'webdav-goftp1';

    return @$raw_names;
}

sub _git_tree_listing_names {
    my ($game, $raw_names) = @_;

    my @names;
    for my $raw (@$raw_names) {
        my $name = _git_tree_visible_name($raw, $game);
        push @names, $name if defined($name) && $name ne '';
    }

    return @names;
}

sub _git_tree_visible_name {
    my ($line, $game) = @_;

    return undef if !defined($line) || $line eq '';

    my $path;
    if ($line =~ /\A[0-7]{6}\s+\S+\s+[0-9a-fA-F]+(?:\s+(?:-|\d+))?\t(.+)\z/) {
        $path = $1;    # git ls-tree default: mode type object<TAB>path
    }
    elsif ($line =~ /\A[0-7]{6}\s+[0-9a-fA-F]+(?:\s+(?:-|\d+))?\s+\S+\s+(.+)\z/) {
        $path = $1;    # mode object type path fixtures
    }
    elsif ($line =~ /\Amode=[0-7]{6}\s+object=[0-9a-fA-F]+\s+type=\S+(?:\s+size=\S+)?\s+path=(.+)\z/) {
        $path = $1;
    }
    elsif ($line =~ m{\A(?:\./)?(?:events|sidecar|projections?|tmp)(?:/|\z)}) {
        $path = $line; # checkout-style relative path
    }

    return undef if !defined($path) || $path eq '';

    $path =~ s{\A(?:\./)+}{};
    $path =~ s{\A\Q$game\E/}{};

    return $path;
}

sub _dns_record_listing_names {
    my ($game, $raw_names) = @_;

    my @names;
    for my $line (@$raw_names) {
        my $event = _dns_record_event_value($line, $game);
        push @names, $event if defined $event;
    }

    return @names;
}

sub _dns_record_event_value {
    my ($line, $game) = @_;

    return undef if !defined $line || $line eq '';

    my $presentation = lc $line;
    return undef if $presentation !~ /(?:\A|\s)type=txt(?:\s|\z)/;

    my ($owner) = $presentation =~ /(?:\A|\s)owner="?([a-z0-9._-]+)"?(?:\s|\z)/;
    return undef if !defined $owner || !_dns_owner_matches_game($owner, $game);

    my ($event) = $presentation =~ /(?:\A|\s)event="?([a-z0-9._-]+)"?(?:\s|\z)/;
    return undef if !defined $event;

    return $event;
}

sub _dns_owner_matches_game {
    my ($owner, $game) = @_;

    my $game_label = lc $game;
    return $owner =~ /(?:\A|[.])\Q$game_label\E(?:[.]|\z)/ ? 1 : 0;
}

sub _webdav_listing_names {
    my ($game, $raw_names) = @_;

    my @names;
    for my $line (@$raw_names) {
        my $href = _webdav_href($line);
        next if !defined $href;

        my $name = _webdav_listing_name_from_href($game, $href);
        push @names, $name if defined $name;
    }

    return @names;
}

sub _webdav_href {
    my ($line) = @_;

    return undef if !defined $line || $line eq '';
    return $1 if $line =~ m{<href>([^<]*)</href>};
    return $1 if $line =~ /\bhref="([^"]*)"/;
    return $1 if $line =~ /\bhref='([^']*)'/;
    return $1 if $line =~ /\bhref=([^\s;]+)/;
    return undef;
}

sub _webdav_listing_name_from_href {
    my ($game, $href) = @_;

    $href =~ s{\Ahttps?://[^/]*}{};
    $href =~ s/[?#].*\z//;

    my @segments = _webdav_href_segments($href);
    for my $i (0 .. $#segments) {
        next if $segments[$i] ne $game;
        next if ($segments[$i + 1] // '') ne 'events';
        next if $i + 2 != $#segments;

        my $basename = $segments[$i + 2];
        next if $basename !~ /\A[a-z0-9._-]+\z/;

        return "events/$basename";
    }

    return undef;
}

sub _webdav_href_segments {
    my ($href) = @_;

    my @segments;
    for my $segment (grep { $_ ne '' } split m{/+}, $href) {
        my $decoded = _percent_decode_once($segment);
        return () if !defined $decoded;
        return () if $decoded eq '.' || $decoded eq '..';
        return () if $decoded =~ m{[/\\\0\r\n]};
        push @segments, $decoded;
    }
    return @segments;
}

sub _percent_decode_once {
    my ($value) = @_;

    return undef if !defined $value;
    return undef if $value =~ /%(?![0-9A-Fa-f]{2})/;

    $value =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
    return $value;
}

sub _args {
    return %{ $_[0] } if @_ == 1 && ref($_[0]) eq 'HASH';
    croak 'named arguments must be key/value pairs' if @_ % 2;
    return @_;
}

sub _required {
    my ($value, $name) = @_;
    croak "$name is required" if !defined($value) || $value eq '';
    return $value;
}

sub _array_ref {
    my ($value, $name) = @_;
    croak "$name must be an array reference" if ref($value) ne 'ARRAY';
    return $value;
}

1;

__END__

=head1 NAME

GobanFTP::Profile::Adapter - read-only v1 profile listing normalizers

=cut
