#!/usr/bin/perl -w
#
# soundconvert
# convert ogg, mp3, flac, ... to ogg, mp3, flac, ... while keeping tag information
#
# 2005-2006,2008-2012,2015,2017 (C) by Christian Garbs <mitch@cgarbs.de>
# licensed under GNU GPL
#

use strict;
use File::Basename qw/ fileparse /;
use File::Type;
use File::Which;
use IO::Handle;
use IPC::Open3;

my $version = '1.47+git';

my $multiple_tracks_key = "__multitracks__";

# check for audio modules on startup
our ($have_audio_flac_header, $have_mp3_info, $have_mp4_info, $have_ogg_vorbis_header, $have_ogg_vorbis_header_pureperl);
BEGIN {
    eval { require Audio::FLAC::Header; };
    $have_audio_flac_header = not $@;
    eval { require MP3::Info; };
    $have_mp3_info = not $@;
    eval { require MP4::Info; };
    $have_mp4_info = not $@;
    eval { require Ogg::Vorbis::Header; };
    $have_ogg_vorbis_header = not $@;
    eval { require Ogg::Vorbis::Header::PurePerl; };
    $have_ogg_vorbis_header_pureperl = not $@;
}

# check for archive/compression modules on startup
our ($have_tar, $have_gzip, $have_unzip);
BEGIN {
    eval { require Archive::Tar; };
    $have_tar = not $@;
    eval { require Compress::Zlib; };
    $have_gzip = not $@;
    eval { require Archive::Zip; };
    $have_unzip = not $@;
}

sub piped_fork($$$$$$);

my $typelist = {

    # TYPE              scalar 'sound'
    # IO                scalar 'i'nput, 'o'utput, 'io'
    # NAME              (scalar)
    # NEW_EXTENSION     (scalar)
    # CHECK_FOR_TOOLS   (coderef returning scalar)
    # GET_INFO          (coderef returning hashref)
    # REMAP_INFO        (hashref)
    # DECODE_TO_WAV     (coderef)
    # ENCODE_TO_NATIVE  (coderef)
    # TAG_NATIVE        (coderef)

    'audio/mpeg' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'MP3',
	NEW_EXTENSION => 'mp3',
	CHECK_FOR_TOOLS => sub {
	    if (not $have_mp3_info) {
		warn "MP3 unavailable: Perl module MP3::Info not found";
		return 0;
	    }
	    unless (defined which('lame') or defined which('toolame')) {
		warn "MP3 unavailable: neither binary lame nor binary toolame not found";
		return 0;
	    }
	    unless (defined which('mpg123')) {
		warn "MP3 unavailable: binary mpg123 not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $tags = MP3::Info::get_mp3tag( shift );
	    delete $tags->{TAGVERSION};
	    foreach my $key (keys %{$tags}) {
		delete $tags->{$key} if $tags->{$key} eq '';
	    }
	    # capitalize KEYS
	    return { map { uc($_) => $tags->{$_} } keys %{$tags} };
	},
	REMAP_INFO => {
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('mpg123','-q','-w','-',$file);
	    print STDERR "  decoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    my $binary = 'lame';
	    unless (defined which($binary)) {
		$binary = 'toolame';
	    }
	    my @call = ($binary,
			'-b','128',
			'-',
			$file
			);

	    print STDERR "  encoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	TAG_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    MP3::Info::set_mp3tag( $file, $tags );
	},

    },

    'video/quicktime' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'AAC',
	NEW_EXTENSION => 'mp4',
	CHECK_FOR_TOOLS => sub {
	    if (not $have_mp4_info) {
		warn "AAC unavailable: Perl module MP4::Info not found";
		return 0;
	    }
	    unless (defined which('faac')) {
		warn "AAC unavailable: binary faac not found";
		return 0;
	    }
	    unless (defined which('faad')) {
		warn "AAC unavailable: binary faad not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $tags = MP4::Info::get_mp4tag( shift ) or return {};
	    foreach my $tag (qw(TAGVERSION NAM ART ALB DAY CMT GNRE TRKN[0] SIZE MS SECS CPIL MM SS LAYER FREQUENCY TOO TIME ENCRYPTED COPYRIGHT ENCODING BITRATE VERSION)) {
		delete $tags->{$tag};
	    } 
	    foreach my $key (keys %{$tags}) {
		delete $tags->{$key} if $tags->{$key} eq '';
	    }
	    # capitalize KEYS
	    return { map { uc($_) => $tags->{$_} } keys %{$tags} };
	},
	REMAP_INFO => {
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('faad','-b','1','-d','-f','2','-q','-w',$file);
	    my @sox = ('sox','-t','.raw','-b','16','-r','44100','-e','signed-integer','-c','2','-','-t','.wav','-');
	    piped_fork
		sub {
		    print STDERR "  decoding: <@call>\n";
		    exec { $call[0] } @call;
		}, 0, 0,
	    sub {
		print STDERR "  filter: <@sox>\n";
		exec { $sox[0] } @sox;
	    }, 0, 0;
	    wait;
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    my @call = ('faac',
			'-b','128');
	    
	    push @call, ('--artist',$tags->{'ARTIST'}) if exists $tags->{'ARTIST'};
	    push @call, ('--writer',$tags->{'WRITER'}) if exists $tags->{'WRITER'};
	    push @call, ('--title',$tags->{'TITLE'}) if exists $tags->{'TITLE'};
	    push @call, ('--genre',$tags->{'GENRE'}) if exists $tags->{'GENRE'};
	    push @call, ('--album',$tags->{'ALBUM'}) if exists $tags->{'ALBUM'};
	    push @call, ('--track',$tags->{'TRACK'}) if exists $tags->{'TRACK'};
	    push @call, ('--year',$tags->{'YEAR'}) if exists $tags->{'YEAR'};
	    push @call, ('--comment',$tags->{'COMMENT'}) if exists $tags->{'COMMENT'};

	    push @call, ('-o', $file,
			 '-');

	    print STDERR "  encoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	TAG_NATIVE => sub {
	    # done at encoding time
	},

    },

    'application/ogg' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'OGG',
	NEW_EXTENSION => 'ogg',
	CHECK_FOR_TOOLS => sub {
	    if (not ($have_ogg_vorbis_header or $have_ogg_vorbis_header_pureperl)) {
		warn "OGG unavailable: neither Perl module Ogg::Vorbis::Header nor Ogg::Vorbis::Header::PurePerl found";
		return 0;
	    }
	    unless (defined which('oggenc')) {
		warn "OGG unavailable: binary oggenc not found";
		return 0;
	    }
	    unless (defined which('oggdec')) {
		warn "OGG unavailable: binary oggdec not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $ogg = $have_ogg_vorbis_header ? Ogg::Vorbis::Header->new( shift ) : Ogg::Vorbis::Header::PurePerl->new( shift );
	    my $tags = {};
	    foreach my $key ($ogg->comment_tags) {
		$tags->{uc $key} = join ' ', $ogg->comment($key);
	    }
	    return $tags;
	},
	REMAP_INFO => {
	    'TRACKNUMBER' => 'TRACKNUM',
	    'DATE' => 'YEAR',
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('oggdec','-Q','-o','-',$file);
	    print STDERR "  decoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = \%{shift()};
	    my @call = ('oggenc',
			'-Q',       # quiet
			'-q','6'   # quality
			);
	    
	    push @call, ('-d',$tags->{'YEAR'}) if exists $tags->{'YEAR'};
	    push @call, ('-N',$tags->{'TRACKNUM'}) if exists $tags->{'TRACKNUM'};
	    push @call, ('-t',$tags->{'TITLE'}) if exists $tags->{'TITLE'};
	    push @call, ('-l',$tags->{'ALBUM'}) if exists $tags->{'ALBUM'};
	    push @call, ('-a',$tags->{'ARTIST'}) if exists $tags->{'ARTIST'};
	    push @call, ('-G',$tags->{'GENRE'}) if exists $tags->{'GENRE'};

	    delete $tags->{'YEAR'};
	    delete $tags->{'TRACKNUM'};
	    delete $tags->{'TITLE'};
	    delete $tags->{'ALBUM'};
	    delete $tags->{'ARTIST'};
	    delete $tags->{'GENRE'};
	    foreach my $key (keys %{$tags}) {
		push @call, ('-c', "$key=$tags->{$key}");
	    }
	    push @call, ('-',
			 '-o', $file);

	    print STDERR "  encoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	TAG_NATIVE => sub {
	    # done at encoding time
	},
    },

    'audio/x-mod' => {

	TYPE => 'sound',
	IO => 'i',
	NAME => 'MOD',
	NEW_EXTENSION => '',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('mikmod')) {
		warn "MOD unavailable: binary mikmod not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    # no tags yet
	    return {};
	},
	REMAP_INFO => {
	    # no tags yet
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('mikmod','-o','16s','-f','44100','--hqmixer','--nosurround','--nofadeout','--noloops','--exitafter','-q','-d','11',$file);
	    my @sox = ('sox','-t','.raw','-b','16','-r','44100','-e','signed-integer','-c','2','-','-t','.wav','-');
	    piped_fork
		sub {
		    print STDERR "  decoding: <@call>\n";
		    exec { $call[0] } @call;
		}, 0, 0,
	    sub {
		print STDERR "  filter: <@sox>\n";
		exec { $sox[0] } @sox;
	    }, 0, 0;
	    wait;
	},
	ENCODE_TO_NATIVE => sub {
	    die "  can't encode to mod!";
	},
	TAG_NATIVE => sub {
	},
    },

    'audio/monkey' => {

	TYPE => 'sound',
	IO => 'i',
	NAME => 'APE',
	NEW_EXTENSION => '',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('mac')) {
		warn "APE unavailable: binary mac not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    # no tags yet
	    return {};
	},
	REMAP_INFO => {
	    # no tags yet
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('mac',$file,'-','-d');
	    print STDERR "  decoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	ENCODE_TO_NATIVE => sub {
	    die "  can't encode to mod!";
	},
	TAG_NATIVE => sub {
	},
    },

    'audio/x-wav' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'WAV',
	NEW_EXTENSION => 'wav',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('sox')) {
		warn "WAV unavailable: binary sox not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    # no tags
	    return {};
	},
	REMAP_INFO => {
	    # no tags
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('sox',$file,'-t','.wav','-b','16','-r','44100','-e','signed-integer','-c','2','-');
	    print STDERR "  decoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    # re-encode to fix length parameter!
	    my @call = ('sox','-t','.wav','-','-t','.wav',$file);
	    print STDERR "  encoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	TAG_NATIVE => sub {
	},
    },

    'audio/flac' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'FLAC',
	NEW_EXTENSION => 'flac',
	CHECK_FOR_TOOLS => sub {
	    if (not $have_audio_flac_header) {
		warn "FLAC unavailable: Perl module Audio::FLAC::Header not found";
		return 0;
	    }
	    unless (defined which('flac')) {
		warn "FLAC unavailable: binary flac not found";
		return 0;
	    }
	    unless (defined which('metaflac')) {
		warn "FLAC unavailable: binary metaflac not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $tags = Audio::FLAC::Header->new( shift )->tags;
	    delete $tags->{VENDOR};
	    # capitalize KEYS
	    return { map { uc($_) => $tags->{$_} } keys %{$tags} };
	},
	REMAP_INFO => {
	    'TRACKNUMBER' => 'TRACKNUM',
	    'DATE' => 'YEAR',
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('flac','-s','-d','-c',$file);
	    print STDERR "  decoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    my @call = ('flac','-s','-f','-o',$file,'-');
	    print STDERR "  encoding: <@call>\n";
	    exec { $call[0] } @call;
	},
	TAG_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    open TAGS, '|-', ('metaflac', '--import-tags-from=-', $file) or die "can't open metaflac: $!";
	    foreach my $key (keys %{$tags}) {
		print TAGS "$key=$tags->{$key}";
	    }
	    close TAGS or die "can't close metaflac: $!";
	},
	
    },
    
    'audio/gbs' => {

	TYPE => 'sound',
	IO => 'i',
	NAME => 'GBS',
	NEW_EXTENSION => 'gbs',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('gbsplay')) {
		warn "GBS unavailable: binary gbsplay not found";
		return 0;
	    }
	    unless (defined which('gbsinfo')) {
		warn "GBS unavailable: binary gbsinfo not found";
		return 0;
	    }
	    unless (defined which('sox')) {
		warn "GBS unavailable: binary sox not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $file = shift;
	    my $tags = {};
	    open GBSINFO, '-|', ('gbsinfo', $file) or die "can't open gbsinfo: $!";
	    while (my $line = <GBSINFO>) {
		chomp $line;
		next unless $line =~ /^([^:]+):\s+"?(.*?)"?$/;
		my ($key, $value) = ($1, $2);
		if ($key eq 'Title') {
		    $tags->{TITLE} = $value;
		} elsif ($key eq 'Author') {
		    $tags->{ARTIST} = $value;
		} elsif ($key eq 'Copyright') {
		    $tags->{COMMENT} = $value;
		} elsif ($key eq 'Subsongs') {
		    $tags->{$multiple_tracks_key} = $value;
		}
	    }
	    close GBSINFO or die "can't close gbsinfo: $!";
	    return $tags;
	},
	REMAP_INFO => {
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my $track = shift;
	    my @call = ('gbsplay','-o','stdout','-r','44100','-g','0','-f','6','-t','165',$file,$track,$track);
	    my @sox = ('sox','-t','.raw','-b','16','-r','44100','-e','signed-integer','-c','2','-','-t','.wav','-');
	    piped_fork
		sub {
		    print STDERR "  decoding: <@call>\n";
		    exec { $call[0] } @call;
		}, 0, 0,
	    sub {
		print STDERR "  filter: <@sox>\n";
		exec { $sox[0] } @sox;
	    }, 0, 0;
	    wait;
	},
	ENCODE_TO_NATIVE => sub {
	    die "can't encode to gbs!";
	},
	TAG_NATIVE => sub {
	},
	
    },

    'audio/sid' => {

	TYPE => 'sound',
	IO => 'i',
	NAME => 'SID',
	NEW_EXTENSION => 'sid',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('sidplay2')) {
		warn "SID unavailable: binary sidplay2 not found";
		return 0;
	    }
	    unless (defined which('sox')) {
		warn "SID unavailable: binary sox not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $file = shift;
	    my $tags = {};

	    my ($chld_out, $chld_in);
	    my $pid = open3( $chld_in, $chld_out, 0, (qw(sidplay2 -q -t1 -w/dev/null), $file) );
	    while (my $line = <$chld_out>) {
		chomp($line);
		$line =~ s/\r//; # urks, sidplay2 uses \r for output formatting
		$line =~ s/^\s+\|\|\s+//;
		if ($line =~ /^(Title|Author|Released)\s+:\s(.*?)\s*$/) {
		    $tags->{uc($1)} = $2;
		} elsif  ($line =~ m|^Playlist\s+:\s\d+/\d+\s+\(tune \d+/(\d+).*?\)|) {
		    $tags->{$multiple_tracks_key} = $1;
		}
	    }
	    waitpid $pid, 0;
	    
	    return $tags;
	},
	REMAP_INFO => {
	    'AUTHOR' => 'ARTIST',
	    'RELEASED' => 'YEAR',
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my $track = shift;
	    my $tmpfile = $file . '~~temp~~' . $$;
	    my @call = ('sidplay2','-q','-w'.$tmpfile,'-t3:30','-os','-o'.$track,$file);
	    my @sox = ('sox','-t','.raw','-b','16','-r','44100','-e','signed-integer','-c','1',$tmpfile,'-t','.wav','-');

	    # no piping possible!
	    system @call;
	    system @sox;
	    unlink $tmpfile;
	    exit 0;
	},
	ENCODE_TO_NATIVE => sub {
	    die "can't encode to sid!";
	},
	TAG_NATIVE => sub {
	},
	
    },

    'audio/x-midi' => {

	TYPE => 'sound',
	IO => 'i',
	NAME => 'MID',
	NEW_EXTENSION => '',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('timidity')) {
		warn "MID unavailable: binary timidity not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    # no tags yet
	    return {};
	},
	REMAP_INFO => {
	    # no tags yet
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my @call = ('timidity','-a','-Ow','-o','-','-idqq','--no-loop','-k','0','-Ow','--output-stereo','--output-16bit','-s','44100',$file);
	    my @sox = ('sox','-t','.raw','-b','16','-r','44100','-e','signed-integer','-c','2','-','-t','.wav','-');
	    piped_fork
		sub {
		    print STDERR "  decoding: <@call>\n";
		    exec { $call[0] } @call;
		}, 0, 0,
	    sub {
		print STDERR "  filter: <@sox>\n";
		exec { $sox[0] } @sox;
	    }, 0, 0;
	    wait;
	},
	ENCODE_TO_NATIVE => sub {
	    die "can't encode to mid!";
	},
	TAG_NATIVE => sub {
	},
    },

    'video/x-flv' => {

	TYPE => 'sound',
	IO => 'i',
	NAME => 'FLV',
	NEW_EXTENSION => 'flv',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('mplayer')) {
		warn "FLV unavailable: binary mplayer not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    # no tags yet
	    return {};
	},
	REMAP_INFO => {
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    my $tmpfile = $file . '~~temp~~' . $$;
	    my @call = ('mplayer','-really-quiet','-vc','copy','-vo','null',
			'-ao', 'pcm:file="'.$tmpfile.'":fast',$file);
	    my @cat = ('cat',$tmpfile);

	    # no piping possible!
	    system @call;
	    system @cat;
	    unlink $tmpfile;
	    exit 0;
	},
	ENCODE_TO_NATIVE => sub {
	    die "can't encode to flv!";
	},
	TAG_NATIVE => sub {
	},
	
    },

    # TYPE              scalar 'archive'
    # NAME              (scalar)
    # CHECK_FOR_TOOLS   (coderef returning scalar)
    # UNARCHIVE         (coderef returning array)

    'application/x-gtar' => {

	TYPE => 'archive',
	NAME => 'TAR',
	CHECK_FOR_TOOLS => sub {
	    unless ($have_tar) {
		warn "TAR unavailable: Perl module Archive::Tar not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my @newfiles;
	    my $tar = Archive::Tar->new($file);
	    die "error opening TAR archive\n" unless defined $tar;
	    
	    foreach my $file ($tar->get_files) {
		$tar->extract_file($file->full_path, $file->name);
		push @newfiles, $file->name;
	    }
	    return @newfiles;
	}
	
    },
	
    'application/x-gzip' => {

	TYPE => 'archive',
	NAME => 'GZIP',
	CHECK_FOR_TOOLS => sub {
	    unless ($have_gzip) {
		warn "GZIP unavailable: Perl module Compress::Zlib not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my $newfile = $file;
	    $newfile .= '.gunzip' unless ($newfile =~ s/.gz$//);

	    my $buffer ;

	    my $gz = Compress::Zlib::gzopen($file, "rb")
		or die "can't open $file: $!\n" ;
	    open GUNZIP, '>', $newfile or die "can't open $newfile: $!\n";

	    print GUNZIP $buffer while $gz->gzread($buffer) > 0 ;
# TODO: error handling does not work?
#	    my $gzerrno = $gz->gzerror;
#
#	    die "Error reading from $file: $gzerrno" . ($gzerrno+0) . "\n"
#		if $gzerrno ne 'Z_STREAM_END' ;

	    $gz->gzclose();
	    close GUNZIP or die "can't close $newfile: $!\n";
	    
	    return ($newfile);
	},
	
    },

    'application/x-bzip2' => {

	TYPE => 'archive',
	NAME => 'BZIP2',
	CHECK_FOR_TOOLS => sub {
	    unless (defined which('bunzip2')) {
		warn "BZIP2 unavailable: binary bunzip2 not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my $newfile = $file;
	    $newfile .= '.bunzip2' unless ($newfile =~ s/.bz2$//);

	    piped_fork
		sub {
		    my @call = ('bunzip2', '--stdout', '--keep', $file);
		    exec { $call[0] } @call;
		}, 0, 0,
	    sub {
		my @call = ('dd',"of=$newfile");
		exec { $call[0] } @call;
	    }, 0, 0;

	    wait;
	    
	    return ($newfile);
	}
	
    },

    'application/zip' => {

	TYPE => 'archive',
	NAME => 'ZIP',
	CHECK_FOR_TOOLS => sub {
	    unless ($have_unzip) {
		warn "ZIP unavailable: Perl module Archive::Zip not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my @newfiles;
	    my $zip = Archive::Zip->new($file);
	    die "error opening ZIP archive\n" unless defined $zip;
	    
	    foreach my $member ($zip->members) {
		$zip->extractMemberWithoutPaths( $member );
		push @newfiles, $member->fileName();
	    }
	    return @newfiles;
	}
	
    }

};


# get temporary directory for archive extraction
#my $tempdir = tempdir( TMPDIR => 1, CLEANUP => 1);

# default encoder is MP3
my $encoder = $typelist->{'audio/mpeg'};

# rename to FAT?
my $rename_fat = 0;

# check for configuration file
my $rcfile = "$ENV{HOME}/.soundconvertrc";
if (-r $rcfile) {
    eval(`cat "$rcfile"`);
    die "  while loading $rcfile:\n$@\n" if $@;
}

# check available backends
foreach my $type (keys %{$typelist}) {
    delete $typelist->{$type} unless &{$typelist->{$type}->{CHECK_FOR_TOOLS}}();
}

# map multiple input types
# TODO use $NAME as key, make type a member array
$typelist->{'audio/x-ft2-mod'} = $typelist->{'audio/x-mod'};
$typelist->{'audio/x-protracker-mod'} = $typelist->{'audio/x-mod'};
$typelist->{'audio/x-st3-mod'} = $typelist->{'audio/x-mod'};
$typelist->{'audio/x-669-mod'} = $typelist->{'audio/x-mod'};
$typelist->{'audio/x-fasttracker-mod'} = $typelist->{'audio/x-mod'};
$typelist->{'audio/midi'} = $typelist->{'audio/x-midi'};

sub helptext() {
    print <<"EOF";
soundconvert $version

Usage:  soundconvert.pl [-h] [-f] [-o format] infile [infile [...]]
  -h          print help text and exit
  -f          remove non-FAT characters from output file
              (warning: might overwrite existing files!)
  -o format   choose output format (default: $encoder->{NAME})
              available formats are:
EOF
    ;
    foreach my $type (keys %{$typelist}) {
	if (exists $typelist->{$type}->{TYPE} and $typelist->{$type}->{TYPE} eq 'sound'
	    and exists $typelist->{$type}->{IO} and $typelist->{$type}->{IO} =~ /o/ ) {
	    print "              ". lc $typelist->{$type}->{NAME} ."\n";
	}
    }
    print "Available input formats are:\n ";
    my %inputlist;
    foreach my $type (keys %{$typelist}) {
	if (exists $typelist->{$type}->{TYPE} and $typelist->{$type}->{TYPE} eq 'sound'
	    and exists $typelist->{$type}->{IO} and $typelist->{$type}->{IO} =~ /i/ ) {
	    $inputlist{lc $typelist->{$type}->{NAME}}++;
	}
    }
    print " $_" foreach (sort keys %inputlist);
    print "\n";
}

if (not defined $ARGV[0] or $ARGV[0] eq '-h') {
    helptext();
    exit 0;
}

sub typelist_find($)
# search a typelist entry by NAME
{
    my $name = lc shift;
    foreach my $type (keys %{$typelist}) {
	if (lc $typelist->{$type}->{NAME} eq $name) {
	    return $typelist->{$type};
	}
    }
    return 0;
}

sub recode($$$$$$)
# reencoding and tagging
{
    my ($handle, $encoder, $file, $newfile, $tags, $track) = @_;

    # rename output file
    if ($rename_fat) {
	$newfile =~ tr/:\\\"?/_/;
    }

    print "newfile: <$newfile>\n";
    piped_fork
	$handle->{DECODE_TO_WAV}, $file, $track,
	$encoder->{ENCODE_TO_NATIVE}, $newfile, $tags;
    
    wait;
    &{$encoder->{TAG_NATIVE}}($newfile, $tags);
}


if ($ARGV[0] eq '-f') {
    shift @ARGV;
    $rename_fat = 1;
}

if ($ARGV[0] eq '-o') {
    shift @ARGV;
    my $type = shift @ARGV;
    die "no output format given with -o" unless defined $type;
    die "output format not available" unless typelist_find($type);
    die "output format not available" unless typelist_find($type)->{TYPE} eq 'sound';
    die "output format not available" unless typelist_find($type)->{IO} =~ /o/;
    $encoder = typelist_find($type);
}

# ugly, try to be position independent...
# better try getopts :-)
if ($ARGV[0] eq '-f') {
    shift @ARGV;
    $rename_fat = 1;
}

my @files = map { { NAME=> $_, DELETE => 0 } } @ARGV;

sub process_soundfile($$)
# process a soundfile (convert it)
{
    my ($file, $handle) = @_;

    # get comments and tags
    my $tags = &{$handle->{GET_INFO}}($file);
	
    # remap comments
    foreach my $key (keys %{$handle->{REMAP_INFO}}) {
	if (exists $tags->{$key}) {
	    $tags->{$handle->{REMAP_INFO}->{$key}} = $tags->{$key};
	    delete $tags->{$key};
	}
    }
    print "tags:\n";
    foreach my $tag (keys %{$tags}) {
	print "\t<$tag> => <$tags->{$tag}>\n";
    }
    print "/tags\n";
    
    if (exists $tags->{$multiple_tracks_key}) {
	my $track_count = $tags->{$multiple_tracks_key};
	my $len = length($track_count);
	$len = 2 if $len<2;
	
	# remove key so it does not get tagged
	delete $tags->{$multiple_tracks_key};

	for my $track (1..$track_count) {
	    my $printtrack = sprintf "%0${len}d", $track;
	    my $newfile = "$file.$printtrack.$encoder->{NEW_EXTENSION}";
	    $tags->{TRACKNUM} = $track;
	    recode($handle, $encoder, $file, $newfile, $tags, $track);
	}
    } else {
	my $newfile = "$file.$encoder->{NEW_EXTENSION}";
	recode($handle, $encoder, $file, $newfile, $tags, 1);
    }
}

sub process_archive($$)
# process an archive (extract it)
{
    my ($file, $handle) = @_;

    my @newfilenames = $handle->{UNARCHIVE}($file);

    foreach my $newfilename (@newfilenames) {
	unshift @files, { NAME => $newfilename, DELETE => 1 };
    }
}


sub process_file($)
# process a given file
{
    my $file = shift;
    my $filename = $file->{NAME};

    print "filename: <$filename>\n";

    if (-d $filename) {
	warn "file <$filename> is a directory...skipping.\n";
	return;
    }
    if (! -e $filename) {
	warn "file <$filename> does not exist...skipping.\n";
	return;
    }
    if (! -r $filename) {
	warn "file <$filename> is not readable...skipping.\n";
	return;
    }

    # determine filetype
    my $ft = File::Type->new();

    my $type = $ft->mime_type($filename);
    print "filetype: <$type>\n";

# TODO schön und allgemeingültig! machen!
# Sonderlocken für alles, was `file -i` nicht richtig meldet
    if ($type eq 'audio/mp3') {
	    $type = 'audio/mpeg';
    } elsif ($type eq 'application/octet-stream') {
	my $filetype = $ft->checktype_filename($filename);

	if ( ($filetype =~ /gzip compressed data/)
	     or ($filename =~ /\.gz$/i ) ) {
	    $type = 'application/gzip';
	} elsif ( ($filetype =~ /FLAC audio bitstream data/)
		  or ($filename =~ /\.flac$/i ) ) {
	    $type = 'audio/flac';
	} elsif ( $filename =~ /\.(it|mod)$/i ) {
	    $type = 'audio/x-mod';
	} elsif ($filename =~ /\.gbs$/i) {
	    $type = 'audio/gbs';
	} elsif ($filename =~ /\.ogg$/i ) {
	    $type = 'application/ogg';
	} elsif ($filename =~ /\.ape$/i ) {
	    $type = 'audio/monkey';
	} elsif ($filename =~ /\.mp3$/i ) {
	    $type = 'audio/mpeg';
	} elsif ($filename =~ /\.sid$/i ) {
	    $type = 'audio/sid';
	} elsif ($filename =~ /\.flv$/i ) {
	    $type = 'video/x-flv';
	}
    } elsif ($type =~ 'audio/unknown') {
	my $filetype = $ft->checktype_filename($filename);

	if ( ($filetype =~ /MIDI data/)
	     or ($filename =~ /\.mid$/i ) ) {
	    $type = 'audio/x-midi';
	}
    }

# /TODO

    if (exists $typelist->{$type}) {

	my $handle = $typelist->{$type};
	print "type: $handle->{NAME}\n";
	if ($handle->{TYPE} eq 'sound') {
	    process_soundfile($filename, $handle);
	} elsif ($handle->{TYPE} eq 'archive') {
	    process_archive($filename, $handle);
	} else {
	    die "unkown handler type $handle->{TYPE}";
	}
	
    } else {
	print "no handler found, skipping...\n";
    }
    print "\n";

    if ($file->{DELETE}) {
	print "deleting temporary file <$filename>\n";
	unlink $filename;
    }
}

sub wait_for_childs(@)
# wait for (multiple) child processes
{
    my %childs = map { $_ => $_ } @_;

    while ( keys %childs ) {
	delete $childs{ wait() };
    }
}

sub piped_fork($$$$$$) {

    my ($write_ref, $w_arg_1, $w_arg_2, $read_ref, $r_arg_1, $r_arg_2) = (@_);
    my ($write_handle, $read_handle);
    pipe $read_handle, $write_handle;

    # fork writer
    my $writer_pid = fork();
    return unless defined $writer_pid;
    if ($writer_pid == 0) {
	my $fd = $write_handle->fileno;
	open STDOUT, ">&$fd" or die "couldn't dup write_handle: $!";
	&$write_ref($w_arg_1, $w_arg_2);
	exit;
    }
    close $write_handle;
    
    # fork reader
    my $reader_pid = fork();
    return unless defined $reader_pid;
    if ($reader_pid == 0) {
	my $fd = $read_handle->fileno;
	open STDIN, "<&$fd" or die "couldn't dup read_handle: $!";
	&$read_ref($r_arg_1, $r_arg_2);
	exit;
    }
    close $read_handle;

    # wait for both
    wait_for_childs( $writer_pid, $reader_pid);
}

while (my $file = shift @files) {
    process_file($file);
}
