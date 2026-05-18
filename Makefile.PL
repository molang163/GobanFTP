use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'GobanFTP',
    VERSION_FROM  => 'lib/GobanFTP.pm',
    ABSTRACT      => 'A listing-first Go game protocol over enumerable stores',
    AUTHOR        => 'GobanFTP contributors',
    LICENSE       => 'perl_5',
    MIN_PERL_VERSION => '5.034',
    PREREQ_PM     => {
        'Digest::SHA'    => 0,
        'HTTP::Tiny'     => 0,
        'MIME::Base64'   => 0,
        'Net::FTP'       => 0,
    },
    EXE_FILES     => [
        'script/gobanftp',
    ],
    TEST_REQUIRES => {
        'File::Temp' => 0,
        'Test::More' => 0,
    },
    META_MERGE    => {
        'meta-spec' => { version => 2 },
        prereqs => {
            runtime => {
                recommends => {
                    'Inline'    => 0,
                    'Inline::C' => 0,
                },
            },
        },
    },
);
