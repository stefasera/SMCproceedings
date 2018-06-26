#!/usr/bin/env perl

# ./getEasyChairPDFs.pl (not: ./getEasyChairPDFs.pl :))

# sudo perl -MCPAN -e shell
# install WWW::Scripter     # WWW::Mechanize extension, DOM and JS;
#                           # install this best; installs HTML::DOM etc..
# install WWW::Mechanize    # (takes a while - many dependencies)
# install IO::Prompt
# install HTML::TreeBuilder # for WWW::Mechanize: $mech->content( format => 'text' )
# install PerlIO::Util
# install HTML::TreeBuilder::XPath

use strict;
use warnings;
use utf8;
use charnames ':full';
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");

use IO::Prompt;   # password prompt input
use IO::Handle;   # for the tee PerlIO thing
use PerlIO::Util; # for the tee PerlIO thing
use File::Path qw(make_path remove_tree); # create dir direct

# WWW::Scripter cannot dump_links etc;
#  use WWW::Mechanize and HTML::DOM separately
use HTML::DOM;
use WWW::Mechanize;
use HTML::TreeBuilder::XPath;
use XML::XPath::XMLParser;    # for as_string for XPath


my $mech;
my ($data_file, $raw_sdata);
my ($htbx_tree, $nb);
my @nodelist_rows;
my %review_all_hash = ();
my @paper_status_array = ();
my $answer = "";

# sample dl link:
# http://www.easychair.org/conferences/submission_download.cgi?a=c089bf10bb54;submission=958204
# "smc2012_submission_134.pdf"
# here we'll dl directly to filename "134.pdf"

# defaut is https://www.easychair.org/account/signin.cgi
my $conference_id = "smc2012";                    # conference ID
my $ec_urlS = "https://www.easychair.org";   # EasyChair base URL, secure
my $ec_url = "http://www.easychair.org";   # EasyChair base URL (for download)
# my $signin_url = "https://www.easychair.org/account/signin.cgi?conf=smc2012";
my $signin_url = $ec_urlS . "/account/signin.cgi?conf=" . $conference_id;
my $pdfdlurl = ""; #"$ec_url/conferences/" . $htmp{'dlurlRA'} ;

my $num_accepted = 0; # total pdfs accepted
my $num_total = 0;    # total pdfs submitted
my $ra_total = 0;     # total pdfs submitted (via review_all.cgi)
my $dlcbtotal = 0;    # dl callback total
my $dl_cbslow = 0;    # "slowdown" for dl callback terminal printout
my $itot = 0;         # tmp counter
my $icnt = 0;         # tmp counter

my $texinputstring = "";
my $pdfdir = "proceedings/pdfs";

my $texinputfilename = "papers_list_${conference_id}.tex";
my $texmasterfilename = "Proceedings_${conference_id}.tex";

my $pdf_filename = ""; # keep global

my $tmpcont;    # temporary var for WWW::Mechanize content
my $mresponse;  # response (status) from WWW::Mechanize

my $webhash = "";
my $reviewall_url = $ec_urlS . "/conferences/review_all.cgi?" . $webhash; # reminder; repeated below
my $fnlogRA = "_getEasyChair_review_all.txt";
my $statusall_url = $ec_urlS . "/conferences/status.cgi?" . $webhash;     # reminder; repeated below
my $fnlogST = "_getEasyChair_status_all.txt";
my $signout_url = $ec_urlS . "/account/signout.cgi?" . $webhash;          # reminder; repeated below
my $fnlogSO = "_getEasyChair_signout.txt";

# to clean tempfiles:
# rm _getEasyChair*
# rm -rf proceedings # if needed


sub printMechData {
  print "Got: " . $mech->title() . "\n";
  print "   base: " . $mech->base() . "\n\n";
  #~ print "   uri: " . $mech->uri() . "\n"; # here, seems uri == base ?! so not printing
  #~ print $mech->content(); # everything
}

sub pauseForAbit {
  # Sleep for 2500 milliseconds
  print("(pause...)\n");
  select(undef, undef, undef, 2.5);
}


# recreate empty log file and start logging
my $logfilename="_getEasyChairPDFs.log";
open(FH,'>'.$logfilename) or die "Can't create $logfilename: $!";
close(FH);
for (*STDOUT, *STDERR) {
  $_->autoflush; $_->push_layer(tee => ">>".$logfilename);
}



$| = 1; # flush output buffer - for prompt prints

print "Enter EasyChair User name [+ENTER]: ";
my $username = <STDIN>;
chomp($username); # remove trailing \n

print "Enter EasyChair ";
my $password = prompt('Password [+ENTER]: ', -e => '*');



# note - WWW::Mechanize implicitly also keeps cookies
$mech = WWW::Mechanize->new();
$mech->agent_alias( 'Linux Mozilla' );
$mech->add_header(
"Connection" => "keep-alive",
"Keep-Alive" => "115");


print("\n");
print("Going to access $signin_url\n");
$mresponse = $mech->get( $signin_url );     #############
if (!$mresponse->is_success) {
  die "Page unreachable $signin_url: ",  $mresponse->status_line, "\n";
}
printMechData();


# note: <input value="smc2012" name="conf" type="hidden"/>

# set username, password as sequential fields
$mech->set_visible( $username, $password );

pauseForAbit();



print("\n");
print("Going to sign in\n");
$mresponse = $mech->click( "Sign in" );     #############
if (!$mresponse->is_success) {
  die "Page unreachable $signin_url: ",  $mresponse->status_line, "\n";
}
$tmpcont = $mech->content();
printMechData();


# do a regex match to extract webhash on this page
# if content matches this (find link):
# (escape \? to exclude ? from match)
if($tmpcont =~ /\/conferences\/review_all.cgi\?([^']+)'/)
{
  $webhash = $1;
}

pauseForAbit();



# construct the main list page link (review_all.cgi)
# and capture the main list page
$reviewall_url = $ec_urlS . "/conferences/review_all.cgi?" . $webhash;

print("\n");
print("Going to access $reviewall_url\n");
$mresponse = $mech->get( $reviewall_url );     #############
if (!$mresponse->is_success) {
  die "Page unreachable $reviewall_url: ",  $mresponse->status_line, "\n";
}
$tmpcont = $mech->content();
printMechData();

# save content
open (MYREVALLFILE, ">$fnlogRA");
binmode MYREVALLFILE, ":utf8";
print MYREVALLFILE $tmpcont;
close (MYREVALLFILE);

print "Parsing and retrieving PDF download links from review_all.cgi... ";

# instead of open(DAT, $data_file); $raw_sdata = join("", <DAT>);
# we now have $tmpcont still; no need $mech->update_html( $raw_sdata );

$htbx_tree = HTML::TreeBuilder::XPath->new_from_content( $tmpcont );

# find all table rows in review_all.cgi
$nb = $htbx_tree->findnodes( '/html/body//div[@class="ct_tbl"]/table[@class="ct_table"]/tbody/tr');

@nodelist_rows = $nb->get_nodelist;
# hash - no need to preserve sorted order, just key indexing
%review_all_hash = ();
foreach my $rowindex (0..$#nodelist_rows) {
  my $trnode = $nodelist_rows[$rowindex];

  my $paperConfID = $trnode->findvalue( 'td[a][1]' ); # gets only the a in first (tr/)td/a: row: 0 / 134

  my $paperAuthorTitleTDnode = (($trnode->findnodes( 'td[i]' ))->get_nodelist)[0];
  my $papertitle = $paperAuthorTitleTDnode->findvalue( 'i' ); # gets whats inside i in the TDnode

  # get as node so we can detach it - which modifies tree
  my $papertitleNode = (($paperAuthorTitleTDnode->findnodes( 'i' ))->get_nodelist)[0];
  $papertitleNode->detach();
  my $paperauthor = $paperAuthorTitleTDnode->findvalue( 'self::*' );

  my $paperdlurl = $trnode->findvalue( 'td[4]/a/@href' );
  my $paperEasyChairID = "NULL";
  if ($paperdlurl =~ /submission=([^;]+)/) { # if regex match, extract
    $paperEasyChairID = $1;
  }

  # store data in Perl hash (python: dict)
  my %hashPaperInfo = ( 'author' => $paperauthor,
                        'title' => $papertitle,
                        'dlurl' => $paperdlurl,
                        'ecid' => $paperEasyChairID
                      );

  $review_all_hash{ $paperConfID } = \%hashPaperInfo;
}

$ra_total = scalar keys %review_all_hash; # find length/size of hash
print "got $ra_total items.\n";

$htbx_tree->delete; # to avoid memory leaks, if you parse many HTML documents

pauseForAbit();



# construct the status (acc/rej) list page link (status.cgi)
# and capture the status page
$statusall_url = $ec_urlS . "/conferences/status.cgi?" . $webhash;

print("\n");
print("Going to access $statusall_url\n");
$mresponse = $mech->get( $statusall_url );     #############
if (!$mresponse->is_success) {
  die "Page unreachable $statusall_url: ",  $mresponse->status_line, "\n";
}
$tmpcont = $mech->content();
printMechData();

# save content
open (MYSTTALLFILE, ">$fnlogST");
binmode MYSTTALLFILE, ":utf8";
print MYSTTALLFILE $tmpcont;
close (MYSTTALLFILE);

print "Parsing, retrieving status table from status.cgi and merging... ";

$htbx_tree = HTML::TreeBuilder::XPath->new_from_content( $tmpcont );

# find all table rows in status.cgi
$nb = $htbx_tree->findnodes( '/html/body//div[@id="papers"]/table[@class="paperTable"]/tr');

@nodelist_rows = $nb->get_nodelist;
# array - to preserve sorted order
@paper_status_array = ();
foreach my $rowindex (0..$#nodelist_rows) {
  # skip processing if on very first row - it's a header
  if ($rowindex == 0) { next; }

  my $trnode = $nodelist_rows[$rowindex];
  my $paperEasyChairID = $trnode->findvalue( '@id' ); # doublecheck - ecid from attribute id <tr id="r1010704">
  $paperEasyChairID = substr($paperEasyChairID, 1); # remove first character 'r'

  my $paperConfID = $trnode->findvalue( 'td[a][1]' ); # gets only the a in first (tr/)td/a: row: 0 / 134
  my $paperauthor = $trnode->findvalue( 'td[2]/span[@class="nauthors"]' );
  my $papertitle = $trnode->findvalue( 'td[2]/a[@class="title"]' );

  my $paperavgscore = $trnode->findvalue( 'td[4 and contains(@id,"avg")]' );
  my $paperstatus = $trnode->findvalue( 'td[5 and @class="dec"]/b' );

  my $ispaperaccept = 0;
  if ($paperstatus =~ m/accept/i) {
    $ispaperaccept = 1;
  }

  # create here a new hash; save this data
  # then toss into array (so as to preserve sorting of table)
  my %htmpra = %{$review_all_hash{ $paperConfID }};

  my %htmp = (
    confid => $paperConfID,
    ecidRA => $htmpra{'ecid'},
    ecidST => $paperEasyChairID,
    authorRA => $htmpra{'author'},
    authorST => $paperauthor,
    titleRA => $htmpra{'title'},
    titleST => $papertitle,
    dlurlRA => $htmpra{'dlurl'},
    avgscoreST => $paperavgscore,
    pstatusST => $paperstatus,
    isaccept => $ispaperaccept,
  );

  # must reference push here too
  push @paper_status_array, \%htmp;
}
$num_total = scalar @paper_status_array;
print "got $num_total items.\n";

$htbx_tree->delete; # to avoid memory leaks, if you parse many HTML documents



print "Retrieved data; generating TeX input list\n";

$texinputstring = "";
$num_accepted = 0;
foreach my $rowindex (0..$#paper_status_array) {
  my $rowis = sprintf("%02d", $rowindex);
  my %htmpb = %{$paper_status_array[$rowindex]};
  my $texentrystr="";
  if ($htmpb{'isaccept'}) {
    $num_accepted++;
    $texentrystr = <<END;
% paper conf. ID: $htmpb{confid}
% (row $rowindex) accepted: Yes: "$htmpb{pstatusST}" :: avg. score: $htmpb{avgscoreST}
% EasyChair paper ID: review_all: $htmpb{ecidRA} / status: $htmpb{ecidST}
% authors (review_all): $htmpb{authorRA}
% authors (status):     $htmpb{authorST}
% title (review_all):   $htmpb{titleRA}
% title (status):       $htmpb{titleST}
% PDF download URL:
% $ec_url/conferences/$htmpb{dlurlRA}
\\includepdf[pages=-,addtotoc={1,part,1,{$htmpb{titleRA}},paper$htmpb{confid}}]{pdfs/$htmpb{confid}.pdf}
\\addtocontents{toc}{\\protect\\needspace{2\\baselineskip}} % via tocloft
\\cleardoublepage
END
  } else {
    $texentrystr = <<END;
%%% paper conf. ID: $htmpb{confid}
%%% (row $rowindex) accepted: No: "$htmpb{pstatusST}" :: avg. score: $htmpb{avgscoreST}
%%% EasyChair paper ID: review_all: $htmpb{ecidRA} / status: $htmpb{ecidST}
%%% authors (review_all): $htmpb{authorRA}
%%% authors (status):     $htmpb{authorST}
%%% title (review_all):   $htmpb{titleRA}
%%% title (status):       $htmpb{titleST}
%%% PDF download URL:
%%% $ec_url/conferences/$htmpb{dlurlRA}
END
  }
  $texinputstring = $texinputstring . $texentrystr . "\n\n";
}



print "\n";
$| = 1; # flush output buffer - for prompt prints


if (not(-d $pdfdir)) {
  print "Must create directory '$pdfdir' before I can continue. ";
  $answer = prompt('Proceed? [y]: ', -one_char, -yes, -default => 'y');
  $answer =~ /[yY]/ or die("Cannot continue, exiting.\n");
  print "Creating directory $pdfdir\n";
  make_path($pdfdir, {
      verbose => 1,
  });
} else {
  print "Found directory ./$pdfdir\n";
}


print "\n";
print "Should I create (overwrites) papers' list in proceedings/$texinputfilename ";
$answer = prompt('? [y]: ', -one_char, -yes, -default => 'y');
if ($answer =~ /[yY]/) {
  # save data -  no single quotes in open!!
  my $tfname = "proceedings/$texinputfilename";
  open (TEXINPLISTFILE, ">$tfname") or die $!;
  binmode TEXINPLISTFILE, ":utf8";
  print TEXINPLISTFILE $texinputstring;
  close (TEXINPLISTFILE);
  print "Generated $tfname\n";
}


print "\n";
print "Should I create (overwrites) master TeX doc in proceedings/$texmasterfilename ";
$answer = prompt('? [y]: ', -one_char, -yes, -default => 'y');
if ($answer =~ /[yY]/) {
  my $texmasterstring = <<'END1' . <<"END2" . <<'END3' . <<"END4" . <<'END';
\documentclass[a4paper,twoside,11pt]{article}
END1
\\newcommand{\\proctitle}{Proceedings of $conference_id}
\\newcommand{\\procauthor}{(Author)}
\\newcommand{\\procsubject}{(Subject)}
\\newcommand{\\prockeywords}{Key, Words}
END2
\usepackage[utf8]{inputenc}
\usepackage{ifthen}   % also defines \isodd
\usepackage{pdfpages} % also loads graphicx
% preserve intern links in pdf
% need to do `pdfannotextractor --install` for PDFBox-0.7.3
% then `pdfannotextractor file.pdf` to extract .pax annotation
\usepackage{pax}

\usepackage{hyperref}
\definecolor{darkblue}{cmyk}{0,0,0,0.9}
\hypersetup{pdftex, colorlinks=true, linkcolor=darkblue, citecolor=darkblue, filecolor=darkblue, pagecolor=darkblue, urlcolor=darkblue}
% note must escape first space in pdftitle
\hypersetup{pdftitle=\proctitle, pdfauthor=\procauthor, pdfsubject=\procsubject, pdfkeywords=\prockeywords}

% add dots in TOC % tlmgr install tocloft - make sure part is def'd
\usepackage{tocloft}
\renewcommand{\cftsecleader}{\cftdotfill{\cftsecdotsep}}
\renewcommand{\cftpartleader}{\bfseries\cftdotfill{\cftdotsep}}

\DeclareUnicodeCharacter{0399}{I} % due corruption in input! Ι U+0399 greek capital letter iota!

% fixes page breaking TOC problems with tocloft/pdfpages
\usepackage{needspace}

\begin{document}

\title{\proctitle}
\author{\procauthor}
\date{\today}

\maketitle
% do not show page numbers until TOC
% must be after \maketitle in standard classes!
% one for this page, and one for the others..
\thispagestyle{empty}
\pagestyle{empty}
\cleardoublepage

\tableofcontents
\cleardoublepage

% global options for pdfpages - add master page counter
\includepdfset{picturecommand={\put(470, 60){{\footnotesize \thepage}}}}

END3
\\input{$texinputfilename}
END4

\end{document}

END
  # save data -  no single quotes in open!!
  my $tfname = "proceedings/$texmasterfilename";
  open (TEXINPLISTFILE, ">$tfname") or die $!;
  binmode TEXINPLISTFILE, ":utf8";
  print TEXINPLISTFILE $texmasterstring;
  close (TEXINPLISTFILE);
  print "Generated $tfname\n";
}


sub dl_callback
{
  my( $data, $response, $proto ) = @_;
  print PDFFILE "$data"; # write data to file
  $dlcbtotal+= length($data);

  # slow down printout a bit - process only every 100th bump
  $dl_cbslow++;
  if ($dl_cbslow == 100) {
    $dl_cbslow = 0;
  } else { return; } # return, not next (no loop here): "Exiting subroutine via next"

  # use int (not floor)
  my $size = $response->header('Content-Length');
  my $dlperc = int(($dlcbtotal/$size)*100);
  my $dlpercd = int($dlperc/10);
  my $dlpercdots = "."x$dlpercd ;
  $size =~ s/(\d{1,3}?)(?=(\d{3})+$)/$1,/g;
  my $sdlcbtotal = "" . $dlcbtotal; # conv. to string!
  $sdlcbtotal =~ s/(\d{1,3}?)(?=(\d{3})+$)/$1,/g;

  my $dlrep = $pdf_filename . " : " . $sdlcbtotal . " / " . $size . " ( $dlperc% ) " . $dlpercdots;
  print "$dlrep\r"; # print percent downloaded
}


print "\n";
print "Should I start a download batch of PDFs for $conference_id ";
$answer = prompt('? [n]: ', -one_char, -yes, -default => 'n');
$itot = 0;
$icnt = 0;
$dlcbtotal = 0;
if ($answer =~ /[yY]/) {
  foreach my $rowindex (0..$#paper_status_array) {
    $itot++;
    my %htmp = %{$paper_status_array[$rowindex]};
    if ($htmp{'isaccept'}) {
      $icnt++;
      $pdf_filename = $htmp{'confid'} . ".pdf";
      $pdfdlurl = "$ec_url/conferences/" . $htmp{'dlurlRA'} ;
      my $pdfpath = "$pdfdir/$pdf_filename";
      print "$icnt/$num_accepted [$itot/$num_total] $pdfpath \n";
      print "   $pdfdlurl \n";
      $dl_cbslow = 0;
      $dlcbtotal = 0;
      open (PDFFILE,">$pdfpath") or die "$!";
      $mresponse = $mech->get($pdfdlurl, ":content_cb" => \&dl_callback);     #############
      if (!$mresponse->is_success) {
        die "File unreachable $pdfdlurl: ",  $mresponse->status_line, "\n";
      }
      print "\n";

      pauseForAbit();

      print "\n";
    }
  }
}

# here everything should be downloaded...

print "\n";
print "Should I run pdfannotextractor (for pax) on all PDFs in $pdfdir ";
$answer = prompt('? [y]: ', -one_char, -yes, -default => 'y');
if ($answer =~ /[yY]/) {
  open(PS,"cd $pdfdir; pdfannotextractor *.pdf 2>&1|") || die "Failed: $!\n";
  while ( <PS> ) {
    print $_;
  }
}

print "\nCompleted batch operation.\n\n";


# be nice - logout at end

$signout_url = $ec_urlS . "/account/signout.cgi?" . $webhash;

print("\n");
print("Logging out - Going to access $signout_url\n");
$mresponse = $mech->get( $signout_url );     #############
if (!$mresponse->is_success) {
  die "Page unreachable $signout_url: ",  $mresponse->status_line, "\n";
}
$tmpcont = $mech->content();
printMechData();

# save content
open (MYLOGOUTFILE, ">$fnlogSO");
print MYLOGOUTFILE $tmpcont;
close (MYLOGOUTFILE);


print "Done. Now you can do:

  cd proceedings
  pdflatex $texmasterfilename
  pdflatex $texmasterfilename # second time for TOC

to generate a proceedings PDF.

Script finished; bye!

";

