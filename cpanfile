requires 'perl', '5.034';
requires 'Digest::SHA';
requires 'Net::FTP';

recommends 'Inline';
recommends 'Inline::C';

on 'test' => sub {
    requires 'Test::More';
    requires 'File::Temp';
};
