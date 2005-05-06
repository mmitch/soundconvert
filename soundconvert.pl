#!/usr/bin/perl -w
# $Id: soundconvert.pl,v 1.11 2005-05-06 17:27:52 mitch Exp $
#
# soundconvert
# convert ogg, mp3, flac, ... to ogg, mp3, flac, ... while keeping tag information
#
# 2005 (C) by Christian Garbs
# licensed under GNU GPL
#

use strict;

my $version = '$Revision: 1.11 $';
$version =~ y/0-9.//cd;

my $multiple_tracks_key = "__multitracks__";

my $typelist = {

    # NAME              (scalar)
    # NEW_EXTENSION     (scalar)
    # CHECK_FOR_TOOLS  (coderef returning scalar)
    # GET_INFO          (coderef returning hashref)
    # REMAP_INFO        (hashref)
    # DECODE_TO_WAV     (coderef returning array)
    # ENCODE_TO_NATIVE  (coderef returning array)
    # TAG_NATIVE        (coderef)

    'audio/mpeg' => {

	NAME => 'MP3',
	NEW_EXTENSION => 'mp3',
	CHECK_FOR_TOOLS => sub {
	    my $have_mp3_info;
	    BEGIN {
		eval { require MP3::Info };
		$have_mp3_info = not $@;
	    }
	    if (not $have_mp3_info) {
		warn "MP3 unavailable: Perl module MP3::Info not found";
		return 0;
	    }
	    if (`which toolame` eq '') {
		warn "MP3 unavailable: binary toolame not found";
		return 0;
	    }
	    if (`which mpg123` eq '') {
		warn "MP3 unavailable: binary mpg123 not found";
		return 0;
	    }
	    return 1;
	},
	GET_INFO => sub {
	    my $tags = get_mp3tag( shift );
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
	    return ('toolame',
		    '-b','128',
		    '-',
		    $file
		    );
	},
	TAG_NATIVE => sub {
	    my $file = shift;
	    my $tags = shift;
	    set_mp3tag( $file, $tags );
	},

    },

    'application/ogg' => {

	NAME => 'OGG',
	NEW_EXTENSION => 'ogg',
	CHECK_FOR_TOOLS => sub {
	    my $have_ogg_vorbis_header;
	    BEGIN {
		eval { require Ogg::Vorbis::Header };
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

    'audio/flac' => {

	NAME => 'FLAC',
	NEW_EXTENSION => 'flac',
	CHECK_FOR_TOOLS => sub {
	    my $have_audio_flac_header;
	    BEGIN {
		eval { require Audio::FLAC::Header };
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
	ENCODE_TO_NATIVE => sub {
	    warn "can't encode to gbs!";
	    return ('dd','of=/dev/null');
	},
	TAG_NATIVE => sub {
	},
	
    }
    
};

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
	print "              ". lc $typelist->{$type}->{NAME} ."\n";
    }
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

if ($ARGV[0] eq '-o') {
    shift @ARGV;
    my $type = shift @ARGV;
    die "no output format given with -o" unless defined $type;
    die "output format not available" unless typelist_find($type);
    $encoder = typelist_find($type);
}

sub recode($$$$$$) {
    my ($handle, $encoder, $file, $newfile, $tags, $track) = @_;

    my $child;
    my @args_dec = &{$handle->{DECODE_TO_WAV}}($file, $track);
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


foreach my $file (@ARGV) {

    print "filename: <$file>\n";

    # determine filetype
    `file -i -- "$file"` =~ /(\S+)$/;
    my $type = $1;
    print "filetype: <$type>\n";

# TODO schön und allgemeingültig! machen!
# Sonderlocke für FLAC und GBS (UGLY!!)
    if ($type eq 'application/octet-stream') {
	if ( ($file =~ /\.flac$/)
	     or (`file "$file"` =~ /FLAC audio bitstream data/)) {
	    $type = 'audio/flac';
	} elsif ($file =~ /\.gbs$/) {
	    $type = 'audio/gbs';
	}
    }
# /TODO

    if (exists $typelist->{$type}) {
	my $handle = $typelist->{$type};
	print "type: $handle->{NAME}\n";

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

    } else {
	print "no handler found, skipping...\n";
    }
    print "\n";
}
