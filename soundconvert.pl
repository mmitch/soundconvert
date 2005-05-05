#!/usr/bin/perl -w
# $Id: soundconvert.pl,v 1.7 2005-05-05 22:16:25 mitch Exp $
#
# soundconvert
# convert ogg, mp3, flac, ... to ogg, mp3, flac, ... while keeping tag information
#
# 2005 (C) by Christian Garbs
# licensed under GNU GPL
#

use strict;
use Audio::FLAC::Header;  # from libaudio-flac-header-perl
use MP3::Info;            # from libmp3-info-perl
use Ogg::Vorbis::Header;  # from libogg-vorbis-header-perl

my $multiple_tracks_key = "__multitracks__";

my $typelist = {

    # NAME              (scalar)
    # NEW_EXTENSION     (scalar)
    # GET_INFO          (coderef returning hashref)
    # REMAP_INFO        (hashref)
    # DECODE_TO_WAV     (coderef returning array)
    # ENCODE_TO_NATIVE  (coderef returning array)
    # TAG_NATIVE        (coderef)

    'audio/mpeg' => {

	NAME => 'MP3',
	NEW_EXTENSION => 'mp3',
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
	GET_INFO => sub {
	    my $file = shift;
	    my $tags = {};
	    open GBSINFO, '-|', ('gbsinfo', $file) or die "can't open gbsinfo: $!";
	    while (my $line = <GBSINFO>) {
		chomp $line;
		next unless $line =~ /^([^:]+):\s+"?(.*)"?$/;
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


# fest verdrahtet: Ausgabe ist MP3
#my $encoder = $typelist->{'audio/flac'};
my $encoder = $typelist->{'audio/mpeg'};
#my $encoder = $typelist->{'application/ogg'};


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
    `file -i "$file"` =~ /(\S+)$/;
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
