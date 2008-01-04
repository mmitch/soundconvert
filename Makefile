PKGNAME=soundconvert
VERSION=$(shell grep \$$Id: soundconvert.pl \
	| head -n 1 | sed -e 's/^.*,v //' -e 's/ .*$$//')

DISTDIR=$(PKGNAME)-$(VERSION)
DISTFILE=$(DISTDIR).tar.gz

BINARIES=soundconvert.pl
CONFIG=soundconvertrc_sample
DOCUMENTS=TODO

FILES=$(BINARIES) $(CONFIG) $(DOCUMENTS)

#MANDIR=./manpages
#POD2MANOPTS=--release=$(VERSION) --center=$(PKGNAME) --section=1

all:	dist

clean:
	rm -f *~
#	rm -rf $(MANDIR)

#generate-manpages:
#	rm -rf $(MANDIR)
#	mkdir $(MANDIR)
#	for FILE in $(BINARIES); do pod2man $(POD2MANOPTS) $$FILE $(MANDIR)/$$FILE.1; done

dist:	clean # generate-manpages
	rm -rf $(DISTDIR)
	mkdir $(DISTDIR)
	cp $(FILES) $(DISTDIR)
#	cp $(MANDIR)/* $(DISTDIR)
	tar -czvf $(DISTFILE) $(DISTDIR)
	rm -rf $(DISTDIR)
