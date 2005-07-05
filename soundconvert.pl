#!/usr/bin/perl -w
# $Id: soundconvert.pl,v 1.23 2005-07-05 18:03:26 mitch Exp $
#
# soundconvert
# convert ogg, mp3, flac, ... to ogg, mp3, flac, ... while keeping tag information
#
# 2005 (C) by Christian Garbs <mitch@cgarbs.de>
# licensed under GNU GPL
#

use strict;
#use File::Temp qw/ tempdir /;
use File::Basename qw/ fileparse /;

my $version = '$Revision: 1.23 $';
$version =~ y/0-9.//cd;

my $multiple_tracks_key = "__multitracks__";

my $global_output_is_raw = 0;  # another dirty hack, global variable

my $typelist = {

    # TYPE              scalar 'sound'
    # IO                scalar 'i'nput, 'o'utput, 'io'
    # NAME              (scalar)
    # NEW_EXTENSION     (scalar)
    # CHECK_FOR_TOOLS   (coderef returning scalar)
    # GET_INFO          (coderef returning hashref)
    # REMAP_INFO        (hashref)
    # OUTPUT_IS_RAW     (scalar) optional
    # DECODE_TO_WAV     (coderef returning array)
    # ENCODE_TO_NATIVE  (coderef returning array)
    # TAG_NATIVE        (coderef)

    'audio/mpeg' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'MP3',
	NEW_EXTENSION => 'mp3',
	CHECK_FOR_TOOLS => sub {
	    my $have_mp3_info;
	    BEGIN {
		eval { require MP3::Info; };
		$have_mp3_info = not $@;
	    }
	    if (not $have_mp3_info) {
		warn "MP3 unavailable: Perl module MP3::Info not found";
		return 0;
	    }
	    if (`which lame` eq '' and `which toolame` eq '') {
		warn "MP3 unavailable: neither binary lame nor binary toolame not found";
		return 0;
	    }
	    if (`which mpg123` eq '') {
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
	    return ('mpg123','-q','-w','-',$file);
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    my $binary = 'lame';
	    if (`which $binary` eq '') {
		$binary = 'toolame';
	    }
	    my @call = ($binary);
	    if ($global_output_is_raw) {
		push @call, (
			     '-r',
			     '-x',
			     '-s','44.1',
			     '-m','j',
			     '--bitwidth','16',
			     );
	    }
	    push @call, (
			 '-b','128',
			 '-',
			 $file
			 );
	    return @call;
	},
	TAG_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    MP3::Info::set_mp3tag( $file, $tags );
	},

    },

    'application/ogg' => {

	TYPE => 'sound',
	IO => 'io',
	NAME => 'OGG',
	NEW_EXTENSION => 'ogg',
	CHECK_FOR_TOOLS => sub {
	    my $have_ogg_vorbis_header;
	    BEGIN {
		eval { require Ogg::Vorbis::Header; };
		$have_ogg_vorbis_header = not $@;
	    }
	    if (not $have_ogg_vorbis_header) {
		warn "OGG unavailable: Perl module Ogg::Vorbis::Header not found";
		return 0;
	    }
	    if (`which oggenc` eq '') {
		warn "OGG unavailable: binary oggenc not found";
		return 0;
	    }
	    if (`which oggdec` eq '') {
		warn "OGG unavailable: binary oggdec not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $ogg = Ogg::Vorbis::Header->new( shift );
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
	    return ('oggdec','-Q','-o','-',$file);
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = \%{shift()};
	    my @call = ('oggenc',
			'-Q',       # quiet
			'-q','6'   # quality
			);
	    
	    if ($global_output_is_raw) {
		push @call, '-r';
	    }

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
	    return @call;
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
	    if (`which mikmod` eq '') {
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
	    return ('mikmod','-o','16s','-f','44100','--hqmixer','--nosurround','--nofadeout','--noloops','--exitafter','-q','-d','6',$file);
	},
	OUTPUT_IS_RAW => 1,
	ENCODE_TO_NATIVE => sub {
	    warn "can't encode to mod!";
	    return ('dd','of=/dev/null');
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
	    if (`which dd` eq '') {
		warn "WAV unavailable: binary dd not found";
		return 0;
	    }
	    if (`which sox` eq '') {
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
	    return ('sox',$file,'-t','.wav','-r','44100','-w','-c','2','-s','-');
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    return ('dd','bs=2048',"of=$file");
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
	    my $have_audio_flac_header;
	    BEGIN {
		eval { require Audio::FLAC::Header; };
		$have_audio_flac_header = not $@;
	    }
	    if (not $have_audio_flac_header) {
		warn "FLAC unavailable: Perl module Audio::FLAC::Header not found";
		return 0;
	    }
	    if (`which flac` eq '') {
		warn "FLAC unavailable: binary flac not found";
		return 0;
	    }
	    if (`which metaflac` eq '') {
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
	    return ('flac','-s','-d','-c',$file);
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    return ('flac','-s','-f','-o',$file,'-');
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
	    if (`which gbsplay` eq '') {
		warn "GBS unavailable: binary gbsplay not found";
		return 0;
	    }
	    if (`which gbsinfo` eq '') {
		warn "GBS unavailable: binary gbsinfo not found";
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
	    return ('gbsplay','-o','stdout','-r','44100','-g','0','-f','6','-t','165',$file,$track,$track);
	},
	OUTPUT_IS_RAW => 1,
	ENCODE_TO_NATIVE => sub {
	    warn "can't encode to gbs!";
	    return ('dd','of=/dev/null');
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
	    if (`which timidity` eq '') {
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
	    return ('timidity','-a','-Ow','-o','-','-idqq','--no-loop','-k','0','-Ow','--output-stereo','--output-16bit','-s','44100',$file);
	},
	OUTPUT_IS_RAW => 1,
	ENCODE_TO_NATIVE => sub {
	    warn "can't encode to mid!";
	    return ('dd','of=/dev/null');
	},
	TAG_NATIVE => sub {
	},
    },

    # TYPE              scalar 'archive'
    # NAME              (scalar)
    # CHECK_FOR_TOOLS   (coderef returning scalar)
    # UNARCHIVE         (coderef returning array)

    'application/x-tar' => {

	TYPE => 'archive',
	NAME => 'TAR',
	CHECK_FOR_TOOLS => sub {
	    if (`which tar` eq '') {
		warn "TAR unavailable: binary tar not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my @newfiles;
	    open TARLIST, "tar -tf $file |" or die "can't open tar: $1";
	    while (my $line = <TARLIST>) {
		chomp $line;
		my $complete = $line;
		my ($filename, $dirname ) = fileparse( $complete, () );
		if ($dirname ne './') {
		    warn "TAR: no subdir support yet, skipping: $complete\n";
		} else {
		    system 'tar','-xf',$file,$filename;
		}
		push @newfiles, $filename;
	    }
	    close TARLIST;
	    return @newfiles;
	}

    },
	
    'application/gzip' => {

	TYPE => 'archive',
	NAME => 'GZIP',
	CHECK_FOR_TOOLS => sub {
	    if (`which gunzip` eq '') {
		warn "GZIP unavailable: binary gunzip not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my $newfile = $file;
	    $newfile .= '.gunzip' unless ($newfile =~ s/.gz$//);
	    
	    system "gunzip < $file > $newfile";
	    
	    return ($newfile);
	},
	
    },

    'application/x-bzip2' => {

	TYPE => 'archive',
	NAME => 'BZIP2',
	CHECK_FOR_TOOLS => sub {
	    if (`which bunzip2` eq '') {
		warn "BZIP2 unavailable: binary bunzip2 not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my $newfile = $file;
	    $newfile .= '.bunzip2' unless ($newfile =~ s/.bz2$//);
	    
	    system "bunzip2 < $file > $newfile";
	    
	    return ($newfile);
	}
	
    },

    'application/x-zip' => {

	TYPE => 'archive',
	NAME => 'ZIP',
	CHECK_FOR_TOOLS => sub {
	    if (`which unzip` eq '') {
		warn "ZIP unavailable: binary unzip not found";
		return 0;
	    }
	    return 1;
	},
	UNARCHIVE => sub {
	    my $file = shift;
	    my @newfiles;
	    open UNZIPLIST, "unzip -Z -1 $file |" or die "can't open unzip: $1";
	    while (my $line = <UNZIPLIST>) {
		chomp $line;
		my $filename = $line;
		system 'unzip','-n','-j',$file,$filename;
		push @newfiles, $filename;
	    }
	    close UNZIPLIST;
	    return @newfiles;
	}
	
    }

};


# get temporary directory for archive extraction
#my $tempdir = tempdir( TMPDIR => 1, CLEANUP => 1);

# check available backends
foreach my $type (keys %{$typelist}) {
    delete $typelist->{$type} unless &{$typelist->{$type}->{CHECK_FOR_TOOLS}}();
}

# fest verdrahtet: Ausgabe ist MP3
#my $encoder = $typelist->{'audio/flac'};
my $encoder = $typelist->{'audio/mpeg'};
#my $encoder = $typelist->{'application/ogg'};

sub helptext() {
    print <<"EOF";
soundconvert $version

Usage:  soundconvert.pl [-h] [-o format] infile [infile [...]]
  -h          print help text and exit
  -o format   choose output format (default: $encoder->{NAME})
              available formats are:
EOF
    ;
    foreach my $type (keys %{$typelist}) {
	if ($typelist->{$type}->{TYPE} eq 'sound' and $typelist->{$type}->{IO} =~ /o/ ) {
	    print "              ". lc $typelist->{$type}->{NAME} ."\n";
	}
    }
    print "Available input formats are:\n ";
    foreach my $type (keys %{$typelist}) {
	if ($typelist->{$type}->{TYPE} eq 'sound' and $typelist->{$type}->{IO} =~ /i/ ) {
	    print " ". lc $typelist->{$type}->{NAME};
	}
    }
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

    my $child;
    my @args_dec = &{$handle->{DECODE_TO_WAV}}($file, $track);
    $global_output_is_raw = $handle->{OUTPUT_IS_RAW};
    my @args_enc = &{$encoder->{ENCODE_TO_NATIVE}}($newfile, $tags);
    print "newfile: <$newfile>\n";
    print "decode_args: <@args_dec>\n";
    print "encode_args: <@args_enc>\n";
    
    # fork working process
    unless ($child = fork()) {
	# read decoded data from stdin
	open STDIN, '-|',  @args_dec;
	# exec ourself to encoding process
	exec { $args_enc[0] } @args_enc;
    }
    if (defined $child) {
	waitpid $child, 0;
	# add tags
	&{$encoder->{TAG_NATIVE}}($newfile, $tags);
    } else {
	warn "fork failed: $!";
    }
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
	my $len = length($tags->{$multiple_tracks_key});
	$len = 2 if $len<2;
	
	for my $track (1..$tags->{$multiple_tracks_key}) {
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
    `file -i -- "$filename"` =~ /(\S+)(, .+)?$/;
    my $type = $1;
    print "filetype: <$type>\n";

# TODO schön und allgemeingültig! machen!
# Sonderlocken für alles, was `file -i` nicht richti meldet
    if ($type eq 'application/octet-stream') {
	if ( (`file -- "$filename"` =~ /gzip compressed data/)
	     or ($filename =~ /\.gz$/i ) ) {
	    $type = 'application/gzip';
	} elsif ( (`file -- "$filename"` =~ /ScreamTracker III Module sound data/)
		  or ($filename =~ /\.s3m$/i ) ) {
	    $type = 'audio/x-mod';
	} elsif ( (`file -- "$filename"` =~ /FLAC audio bitstream data/)
		  or ($filename =~ /\.flac$/i ) ) {
	    $type = 'audio/flac';
	} elsif ($filename =~ /\.gbs$/i) {
	    $type = 'audio/gbs';
	}
    } elsif ($type =~ 'audio/unknown') {
	if ( (`file -- "$filename"` =~ /MIDI data/)
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

while (my $file = shift @files) {
    process_file($file);
}
