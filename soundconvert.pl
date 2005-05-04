#!/usr/bin/perl -w
# $Id: soundconvert.pl,v 1.1 2005-05-04 22:52:19 mitch Exp $
# soundconvert - convert ogg, mp3, flac, ... to ogg, mp3, flac, ... while keeping tag information
#
use strict;
use MP3::Info;            # from libmp3-info-perl
use Ogg::Vorbis::Header;  # from libogg-vorbis-header-perl

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
	    return $tags;
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
		$tags->{$key} = join ' ', $ogg->comment($key);
	    }
	    return $tags;
	},
	REMAP_INFO => {
	    'artist' => 'ARTIST',
	    'album' => 'ALBUM',
	    'tracknumber' => 'TRACKNUM',
	    'date' => 'YEAR',
	    'title' => 'TITLE',
	},
	DECODE_TO_WAV => sub {
	    my $file = shift;
	    return ('oggdec','-Q','-o','-',$file);
	},
	ENCODE_TO_NATIVE => sub {
	    my $file = shift;
	    my $tags = { shift };
	    my @call = ('oggenc',
			'-Q',       # quiet
			'-q','6',   # quality
			'-d',$tags->{'YEAR'},
			'-N',$tags->{'TRACKNUM'},
			'-t',$tags->{'TITLE'},
			'-l',$tags->{'ALBUM'},
			'-a',$tags->{'ARTIST'},
			'-G',$tags->{'GENRE'},
			);
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
	},
	TAG_NATIVE => sub {
	    # done at encoding time
	},
	
    }

};

# fest verdrahtet: Ausgabe ist MP3
my $encoder = $typelist->{'audio/mpeg'};

foreach my $file (@ARGV) {

    print "filename: <$file>\n";

    # determine filetype
    `file -i "$file"` =~ /(\S+)$/;
    my $type = $1;
    print "filetype: <$type>\n";
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


	my $newfile = "$file.$encoder->{NEW_EXTENSION}";
	my @args_dec = &{$handle->{DECODE_TO_WAV}}($file);
	my @args_enc = &{$encoder->{ENCODE_TO_NATIVE}}($newfile, $tags);
	my $child;
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

    } else {
	print "no handler found, skipping...\n";
    }
    print "\n";
}
