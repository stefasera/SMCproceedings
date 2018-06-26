#!/usr/bin/env perl

# ./_test_getEasyChairPDFs.pl
# note: . and - cannot be part of package name!
# package - because of Data::Section...
BEGIN {@ARGV=map glob, @ARGV};
package _test_getEasyChairPDFs;

=head1 Requirements:

sudo perl -MCPAN -e shell

install WWW::Mechanize  # (takes a while - many dependencies)
install IO::Prompt
install HTML::TreeBuilder # for WWW::Mechanize: $mech->content( format => 'text' )
install PerlIO::Util
install WWW::Scripter # WWW::Mechanize extension, DOM and JS; installs HTML::DOM etc..
install HTML::TreeBuilder::XPath # also check; https://metacpan.org/module/HTML::TreeBuilder::XPath
=cut

use strict;
use warnings;
use utf8;
use charnames ':full';
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");
binmode(DATA, ":utf8");
use Data::Section -setup; # install Data::Section
use WWW::Mechanize;
use HTML::DOM;
# WWW::Scripter cannot dump_links etc;
#  use WWW::Mechanize and HTML::DOM separately
#~ use WWW::Scripter;
use IO::Prompt;
use IO::Handle;   # for the tee PerlIO thing
use PerlIO::Util; # for the tee PerlIO thing
use HTML::TreeBuilder::XPath;
use XML::XPath::XMLParser; # for as_string
use File::Path qw(make_path remove_tree); # create dir direct


my $mech;
my ($data_file, $raw_sdata);
my ($htbx_tree, $nb);
my @nodelist_rows;
my %review_all_hash = ();
my @paper_status_array = ();
my $answer = "";
my %htmp;

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
our $rowindex = 0;     # tmp counter, "for" loops -  may need to print it out, keep global; must be "our" to have its value changed globally by foreach iterator!

my $texinputstring = "";
my $texinputplainstring = "";
my $pdfdir = "proceedings/pdfs";

my $texinputfilename = "papers_list_${conference_id}.tex";
my $texinputplainfilename = "papers_list_${conference_id}_plain.tex";
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

my $texhc_statrow; # = (row $rowindex) accepted: Yes: "$htmpb{pstatusST}" :: avg. score: $htmpb{avgscoreST}
my $texhc_ecidstr; # = review_all: $htmpb{ecidRA} / status: $htmpb{ecidST}
my $texhc_authstr; # (review_all): $htmpb{authorRA} ? (status):     $htmpb{authorST}
my $texhc_titlstr; # (review_all):   $htmpb{titleRA} ? (status):       $htmpb{titleST}

my $texhc_napc; # plus comment for non-accepted indent


$| = 1; # flush output buffer - for prompt prints


sub printMechData {
  print "Got: " . $mech->title() . "\n";
  #~ print "   uri: " . $mech->uri() . "\n"; # here, seems uri == base ?! so not printing
  print "   base: " . $mech->base() . "\n\n";
}

sub pauseForAbit {
  # Sleep for 1100 milliseconds
  print("(pause...)\n");
  select(undef, undef, undef, 1.1);
}

sub getFileContents {
  my($mdata_file) = @_;
  open(DAT, $mdata_file) or die("Could not open file: $!");
  #~ @raw_adata=<DAT>;
  binmode(DAT, ":utf8"); # for correct utf8 (was: to avoid "Wide..")
  my $mraw_sdata = join("", <DAT>);
  close(DAT);
  return $mraw_sdata;
}

sub saveFileContents {
  # save data -  no single quotes in open (else no expand)!!
  my ($mtfname, $mtfcontent) = @_;
  open (TEXINPLISTFILE, ">$mtfname") or die $!;
  binmode TEXINPLISTFILE, ":utf8";
  print TEXINPLISTFILE $mtfcontent;
  close (TEXINPLISTFILE);
  print "Generated $mtfname\n";
}

=head1 Note about getExpandedDataSection:
  Note: ALL variables used in the template,
  MUST be declared BEFORE sub getExpandedDataSection!!
  also:
  # regex expanding of variables in Data::Section:
  print "XXXXXXXXX $$template";
  # this DIRECTLY changes section data in $$template and PERMANENTLY!:
  #~ $$template =~ s/(\${\w+})/${1}/eeg;
  # use a copy variable! (my $ttmpl = $$template; works)
  # copy var works; but below cannot match $htmp{confid}:
  #~ $ttemplate =~ s/(\${\w+})/${1}/eeg && print "$1\n";
  # with including also {}' below,
  # now matches ${htmp{confid}} ${htmp{'confid'}}
  $ttmpl =~ s/(\${[\w{}']+})/${1}/eeg && print "$1\n"; #
  # ... howewer that breaks on {${htmp{'confid'}}} - must do a separate function..
=cut
sub getExpandedDataSection {
  my ($datasectiontitle) = @_;
  sub erepl {
=head1 note about erepl regex expansion (with sub):
    when a match comes in: ${htmp{'confid'}} or ${htmp{titleRA}}};
    make sure it first has the correct number of braces!
    then if it has extra, return them as verbatim braces -
     - and expand those braces which are balanced!
    tr/ is regex to count characters;
      my $numOpenBraces = $arg =~ tr/{//;
      but must loop and store in array anyway
    Pretty much can only expect numClose > numOpen braces as special case
      (because the $ breaks from the left/open side (unless syntax error) )
    my (x,c,v) = (0) x 3; # quick initialization of vars
    # splice to remove first entry of split (which is empty)
    # trick to store changed value in different variable:
      ($expexvar = $exvar) =~ s///g ;
=cut
    my $arg = $1;
    my (@openBracePositions, @closeBracePositions);
    my ($result, $offset);
    $offset = 0;
    while ( ($result = index($arg, "{", $offset)) != -1) {
      push @openBracePositions, $result;
      $offset = $result + 1;
    }
    $offset = 0;
    while ( ($result = index($arg, "}", $offset)) != -1) {
      push @closeBracePositions, $result;
      $offset = $result + 1;
    }
    my $numOpenBraces = scalar @openBracePositions;
    my $numCloseBraces = scalar @closeBracePositions;
    my ($braceDiff,$endBracePos,$dblchk) = (0) x 3; # quick ini
    my ($exvar, $remain, $expexvar) = ("") x 3;
    if ($numCloseBraces > $numOpenBraces) {
      $braceDiff = $numCloseBraces - $numOpenBraces;
      # find location of $braceDiff'th CloseBraces character from end
      # or that is, $numOpenBraces'th closing brace
      $endBracePos = $closeBracePositions[$numOpenBraces];
      $dblchk = substr($arg, $endBracePos, 1);
      ($exvar, $remain) = splice( @{[split(/^(.{$endBracePos})/, $arg)]} , 1 );
    } else {
      $exvar = $arg;
    }
    ($expexvar = $exvar) =~ s/(\${[\w{}']+})/$1/eeg;
    die if $@;                  # needed on /ee, not /e
    my $retstr = "$expexvar$remain";
    #print "erepl:  $arg, $numOpenBraces, $numCloseBraces, $braceDiff, $endBracePos, $dblchk, $exvar, $remain - $retstr \n";
    return $retstr;
  };
  #print "getExpandedDataSection ($rowindex): Got $datasectiontitle ...\n";
  my $template = _test_getEasyChairPDFs::->section_data ($datasectiontitle);
  my $etemplate = $$template;
  #~ print "XXXXXXXXX $etemplate";
  # just /e here - calling sub to expand variables; caring about matching braces
  $etemplate =~ s/(\${[\w{}']+})/erepl($1)/eg ; # && print "$1\n";
  #die if $@;                  # needed on /ee, not /e; "$EVAL_ERROR"
  return $etemplate;
}

# -argv, is way wrong - messes up answer y/n answer
#~ $answer = prompt('Proceed? [y]: ', -tty, -one_char, -default => 'y', -yes);
#~ $answer =~ /[yY]/ or print("no.. ");
#~ print("Continuing\n");


$mech = WWW::Mechanize->new();

# note - nothing is output for $mech->dump_links(); if it is WWW::Scripter!
#~ $mech = WWW::Scripter->new();


# read content from file;
# and "push" it into $mech through $mech->update_html


$data_file = "_getEasyChair_review_all.txt";
$raw_sdata = getFileContents($data_file);

#~ print "$raw_sdata\n";
$mech->update_html( $raw_sdata );



=head1 HTML node structure:
----
The main thing in review_all here is this:

<div class="ct_tbl">
  <table cellpadding="0" cellspacing="0" class="ct_table" style="clear:right">
    <thead>
      <tr>
        <th>#</th>
        <th>submission</th>
        ...
        <th>(update review)
          <br/>subreviewer/PC&nbsp;member</th></tr>
    </thead>
    -------------
    <tbody>
    -------------
      <tr class="evenyellow" id="row15">
      01.  <td class="right">  <a name="134">134</a>  </td>
      02.  <td>Johan Broekaert. <i>BACH and WELL-TEMPERAMENTS / A proposal for an objective definition</i></td>
      03.  <td>  <a href="submission_info_show.cgi?number=958204;a=c089bf10bb54"> <img , title="information on submission 134"/>  </a>  </td>
      04.  <td> <a href="submission_download.cgi?a=c089bf10bb54;submission=958204"> <img , title="download submission 134"/> </a> </td>
      05.  <td>  </td>
      06.  <td>  <a href="review_for_paper.cgi?a=c089bf10bb54;paper=958204">  <img , title="view reviews for submission 134"/> </a> </td>
      07.  <td>  <a href="review_form_text.cgi?a=c089bf10bb54;paper=958204">form</a> </td>
      08.  <td>  <a href="review_add.cgi?a=c089bf10bb54;paper=958204"> <img , title="add review for submission 134"/> </a> </td>
      09.  <td>  <a href="revrequest.cgi?a=c089bf10bb54;paper=958204"> <img , title="subreviewers (submission 134)"/> </a> </td>
      10.  <td> </td>
      11.  <td>  <a href="metareview_edit.cgi?a=c089bf10bb54;paper=958204"> <img , title="edit metareview for submission 134"/> </a> </td>
      12.  <td>
          <a href="review_add.cgi?a=c089bf10bb54;revise=1528207;paper=958204">Antonio Rodà (Canazza)</a>
          <br/>
          <a href="review_add.cgi?a=c089bf10bb54;revise=1531329;paper=958204">Dan Tidhar (Mauch)</a>
          <br/>
          <a href="review_add.cgi?a=c089bf10bb54;revise=1540401;paper=958204">Takala</a>
        </td></tr>

So for each tr in table in div class="ct_tbl"; grab td's 01, 02 and 04!

Also: (master easychair ID) number=958204; -> submission=958204; -> paper=958204

BUT - WWW::Mechanize can only deal with images, links and forms - cannot iterate through other DOM elements!

Note: http://cpan.uwinnipeg.ca/htdocs/WWW-Mechanize-Plugin-JavaScript/WWW/Mechanize/Plugin/DOM.pm.html
WWW::Mechanize::Plugin::DOM - HTML Document Object Model plugin for Mech
THIS MODULE IS DEPRECATED. Please use WWW::Scripter instead.

The main thing in status is this:

<div id="papers" style="clear:right">
  <table class="paperTable">
  ------
    <tr>
      <td class="center">#</td>
      <td class="center">
        <span id="at">title</span>
      </td>
      <td class="center">scores</td>
      <td class="center">
        <img alt="average" src="/images/vertical/pvlipwyz.jpeg"/>
      </td>
      <td class="center">decision</td>
    </tr>
  ------
    <tr id="r1010704">
    01.  <td class="right">  <a name="172">172</a> </td>
    02.  <td>  <span class="nauthors" id="a1010704">Matthieu Macret, Philippe Pasquier and Tamara Smyth. </span>   <a class="title" href="review_for_paper.cgi?a=c089bf10bb54;paper=1010704">Automatic Calibration of Modified FM Synthesis to Harmonic Sounds using Genetic Algorithms</a>  </td>
    03.  <td class="score" id="s1010704" onclick="Status.toggleSelection(1010704)" title="click to select or unselect">  <img src="/images/thumbup.gif"/>  <b>2</b>  <span class="confidence">(3)</span>,  <b>2</b>  <span class="confidence">(2)</span>,  <b>3</b>  <span class="confidence">(2)</span></td>
    04.  <td class="right" id="avg1010704">2.3</td>
    05.  <td class="dec" id="d1010704" onclick="return Status.prompt(1010704)" title="click to change"> <b style="color:blue">accept?</b> </td>
    </tr>
=cut






print "Parsing (HTML::TreeBuilder::XPath) content of $data_file ...\n";

$htbx_tree = HTML::TreeBuilder::XPath->new_from_content( $mech->content() );

# find all table rows
$nb = $htbx_tree->findnodes( '/html/body//div[@class="ct_tbl"]/table[@class="ct_table"]/tbody/tr');


# this: review_all.cgi
# %review_all_hash is unsorted - but we just need the key there

@nodelist_rows = $nb->get_nodelist;
%review_all_hash = ();
foreach $rowindex (0..$#nodelist_rows) {
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
$htbx_tree->delete; # to avoid memory leaks, if you parse many HTML documents


# here we have parsed download list - now parse the order from status.cgi
# here use array as master, since we need the sort order


$data_file = "_getEasyChair_status_all.txt";
$raw_sdata = getFileContents($data_file);


print "Parsing (HTML::TreeBuilder::XPath) content of $data_file ...\n";

$mech->update_html( $raw_sdata );

$htbx_tree = HTML::TreeBuilder::XPath->new_from_content( $mech->content() );

# find all table rows
$nb = $htbx_tree->findnodes( '/html/body//div[@id="papers"]/table[@class="paperTable"]/tr');

@nodelist_rows = $nb->get_nodelist;
@paper_status_array = ();
foreach $rowindex (0..$#nodelist_rows) {
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

  my %htmpo = (
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
  push @paper_status_array, \%htmpo;
}
$num_total = scalar @paper_status_array;
print "got $num_total items.\n";

$htbx_tree->delete; # to avoid memory leaks, if you parse many HTML documents



# here @paper_status_array is now sorted and populated with all relevant data;
# can generate .tex and start download queue

$texinputstring = "";
$texinputplainstring = "";
$num_accepted = 0;
foreach $rowindex (0..$#paper_status_array) {
  my $rowis = sprintf("%02d", $rowindex);
  my $texentrystr="";

  %htmp = %{$paper_status_array[$rowindex]};
  $pdfdlurl = "$ec_url/conferences/" . $htmp{'dlurlRA'};

  $texhc_statrow = "(row $rowindex) accepted: ";
  # always take RA as default; show ST if different
  # careful - author, title: check string equality (eq)
  if ($htmp{ecidRA} == $htmp{ecidST}) {
    $texhc_ecidstr = "(review_all == status): $htmp{ecidRA}"
  } else {
    $texhc_ecidstr = "(review_all != status): $htmp{ecidST}";
  }
  if ($htmp{authorRA} eq $htmp{authorST}) {
    $texhc_authstr = "(review_all == status): $htmp{authorRA}"
  } else {
    $texhc_authstr = "(review_all != status): $htmp{authorST}";
  }
  if ($htmp{titleRA} eq $htmp{titleST}) {
    $texhc_titlstr = "(review_all == status): $htmp{titleRA}"
  } else {
    $texhc_titlstr = "(review_all != status): $htmp{titleST}";
  }

  $texhc_napc = "";
  if ($htmp{'isaccept'}) {
    $num_accepted++;
    $texhc_statrow .= "Yes: '$htmp{pstatusST}' :: avg. score: $htmp{avgscoreST}";
    my $expandTplt_texhc = getExpandedDataSection("tex_header_comment");
    my $expandTplt_texle = "";

    # only for first accepted, show old format
    if ($num_accepted == 1) {
      $expandTplt_texle = getExpandedDataSection("tex_list_entry_old");
    } else {
      $expandTplt_texle = getExpandedDataSection("tex_list_entry_new");
    }

    $texentrystr = $expandTplt_texhc . $expandTplt_texle;
    $texinputplainstring = $texinputplainstring . $expandTplt_texle . "\n\n";
  } else {
    $texhc_statrow .= "No: '$htmp{pstatusST}' :: avg. score: $htmp{avgscoreST}";
    $texhc_napc = "%%";
    my $expandTplt_texhc = getExpandedDataSection("tex_header_comment");

    $texentrystr = $expandTplt_texhc;
  }
  $texinputstring = $texinputstring . $texentrystr . "\n\n";
  #~ print $texentrystr , "\n\n";
}


print "\n";
$answer = "";
#~ $| = 1; # flush output buffer - for prompt prints
# prompt -default => 'y' seems to override -yes; -yes seems to just insist on a question if just enter is pressed
if (not(-d $pdfdir)) {
  print "Must create directory '$pdfdir' before I can continue. ";
  $answer = prompt('Proceed? [y]: ', -tty, -one_char, -yes, -default => 'y');
  $answer =~ /[yY]/ or die("Cannot continue, exiting.\n");
  print "Creating directory $pdfdir\n";
  make_path($pdfdir, {
      verbose => 1,
  });
} else {
  print "Found directory ./$pdfdir\n";
}


print "\n";
print "Should I create (overwrites) papers' list in
proceedings/{$texinputfilename,$texinputplainfilename}";
$answer = prompt('? [y]: ', -tty, -one_char, -default => 'y', -yes);
if ($answer =~ /[yY]/) {
  my $tfname = "proceedings/$texinputfilename";
  saveFileContents($tfname, $texinputstring);
  $tfname = "proceedings/$texinputplainfilename";
  saveFileContents($tfname, $texinputplainstring);
}


print "\n";
print "Should I create (overwrites) master TeX doc in proceedings/$texmasterfilename ";
$answer = prompt('? [y]: ', -tty, -one_char, -default => 'y', -yes);
if ($answer =~ /[yY]/) {

  my $texmasterstring = getExpandedDataSection("tex_master_file");
  my $tfname = "proceedings/$texmasterfilename";
  saveFileContents($tfname, $texmasterstring);
}


# see http://stackoverflow.com/questions/1937780/how-can-i-add-a-progress-bar-to-wwwmechanize

#~ open (PDFFILE,">$pdfdir/$pdf_filename") or die "$!";
#~ $mech->get($url, ":content_cb" => \&dl_callback);
$dlcbtotal = 0;
$pdf_filename = ""; # keep global
sub dl_callback
{
    my( $data, $response, $proto ) = @_;
    print PDFFILE "$data"; # write data to file
    $dlcbtotal+= length($data);
    my $size = $response->header('Content-Length');
    my $dlperc = floor(($dlcbtotal/$size)*100);
    my $dlpercd = floor($dlperc/10);
    my $dlpercdots = "."x$dlpercd ;
    my $dlrep = $pdf_filename . " : " .$dlcbtotal . " / " . $size . " ( $dlperc% ) " . $dlpercdots;
    print "$dlrep\r"; # print percent downloaded
}


print "\n";
print "Should I start a download batch of PDFs for $conference_id ";
$answer = prompt('? [y]: ', -tty, -one_char, -default => 'y', -yes);
$itot = 0;
$icnt = 0;
if ($answer =~ /[yY]/) {
  foreach my $rowindex (0..$#paper_status_array) {
    $itot++;
    %htmp = %{$paper_status_array[$rowindex]};
    if ($htmp{'isaccept'}) {
      $icnt++;
      $pdf_filename = $htmp{'confid'} . ".pdf";
      my $dlurl = "$ec_url/conferences/" . $htmp{'dlurlRA'} ;
      print " $icnt/$num_accepted [$itot/$num_total] $pdfdir/$pdf_filename \n $dlurl \n";
      print "\n";
    }
  }
}


print "\n";
print "Should I run pdfannotextractor (for pax) on all PDFs in $pdfdir ";
$answer = prompt('? [y]: ', -tty, -one_char, -default => 'y', -yes);
if ($answer =~ /[yY]/) {
  #~ my $result = `cd $pdfdir; pdfannotextractor *.pdf`;
  # for "real-time" piping of subprocess stdout, use open
  open(PS,"cd $pdfdir; pdfannotextractor *.pdf |") || die "Failed: $!\n";
  while ( <PS> ) {
    print $_;
  }
}




print "\nScript finished; bye!\n";



=head1 note - the regex var expander for Data::Section ...
... is made to match variables in the form:
# ${name}         (not $name )
# ${hash{'key'}}  (not $hash{'key'} )
... note data section needs only backslash \
    at beginning of line escaped!
=cut
__DATA__

__[ tex_header_comment ]__
${texhc_napc}% paper conf. ID: ${htmp{confid}}
${texhc_napc}% ${texhc_statrow}
${texhc_napc}% EasyChair paper ID: ${texhc_ecidstr}
${texhc_napc}% authors:  ${texhc_authstr}
${texhc_napc}% title:    ${texhc_titlstr}
${texhc_napc}% PDF download URL:
${texhc_napc}% ${pdfdlurl}

__[ tex_list_entry_old ]__
\\includepdf[pages=-,addtotoc={1,part,1,%
    {${htmp{titleRA}}}, %
    paper${htmp{confid}}}] %
{pdfs/${htmp{confid}}.pdf}
\\addtocontents{toc}{\protect\needspace{2\baselineskip}} % via tocloft
\\cleardoublepage

__[ tex_list_entry_new ]__
\\includeTocBkmPart{${htmp{confid}}}{%
  ${htmp{authorRA}}
}{%
  ${htmp{titleRA}}
}%
{pdfs/${htmp{confid}}.pdf}

__[ tex_master_file ]__
\\newcommand{\proctitle}{{\Huge Proceedings} \\ of the \\ {\huge\bfseries\uppercase{${conference_id}}}}
\\newcommand{\procauthor}{(Author / Institution)}
\\newcommand{\procsubject}{(Subject)}
\\newcommand{\prockeywords}{Key, Words}

\\documentclass[a4paper,twoside,11pt]{book}
\\usepackage[utf8]{inputenx}
\\usepackage{ifthen}
\\usepackage{pdfpages}
\\usepackage{pax}

\\usepackage[a4paper,twoside,hmargin=3cm]{geometry}

\\usepackage{hyperref}
\\definecolor{darkblue}{cmyk}{0,0,0,0.9}
\\hypersetup{pdftex, colorlinks=true, linkcolor=darkblue, citecolor=darkblue, filecolor=darkblue, pagecolor=darkblue, urlcolor=darkblue}
\\hypersetup{pdftitle=\proctitle, pdfauthor=\procauthor, pdfsubject=\procsubject, pdfkeywords=\prockeywords}

\\usepackage{needspace}

\\usepackage{tocloft}
\\renewcommand{\cfttoctitlefont}{\Large\bfseries}
\\renewcommand{\cftsecleader}{\cftdotfill{\cftsecdotsep}}

\\def\thepart{\arabic{part}}
\\renewcommand{\cftpartleader}{\bfseries\cftdotfill{\cftdotsep}}
\\renewcommand{\cftpartfont}{\normalfont}
\\renewcommand{\cftpartpagefont}{\normalfont\bfseries}
\\renewcommand{\cftpartpresnum}{Paper }
\\renewcommand{\cftpartaftersnum}{:}

\\usepackage{bookmark}
\\usepackage{pageslts}

\\usepackage{fancyhdr}
\\renewcommand{\headrulewidth}{0pt}
\\renewcommand{\footrulewidth}{0pt}
\\fancyhf{}
\\newlength{\pageNumVpos}\setlength{\pageNumVpos}{-2.75cm}
\\cfoot{\raisebox{\pageNumVpos}{\uppercase{smc2012}-\thepage}}

\\includepdfset{pagecommand=\thispagestyle{fancy}}

\\makeatletter
\\def\phantompart{%
 \stepcounter{part}%
 \xdef\@currentHref{part.\thepart}%
 \Hy@raisedlink{\hyper@anchorstart{\@currentHref}\hyper@anchorend}%
}
\\makeatother

% {confid}{author}{title}{pdf-path}
\\newcommand{\includeTocBkmPart}[4]{%
\\phantompart
\\def\tptitle{\thepart\hspace{1em}\ignorespaces \textit{#2} \\ #3}
\\addtocontents{toc}{%           % tocloft: this adds to toc, but NOT bookmark!:
  \protect\contentsline{part}{%
    \thepart\hspace{1em}\ignorespaces %
    \protect\begin{minipage}[t]{0.6\textwidth} %
      \textit{#2} \\ #3 %
    \protect\end{minipage}%
  } %
  {\thepage} %
  {part.\thepart}%
}
% \hypertarget{paper#1}{}                   % [dest=paper#1,
\\bookmark[dest=part.\thepart,view={XYZ}]{%  % PDF index bookmark separately:
\\tptitle%
}
\\addtocontents{toc}{%           % tocloft: to ensure proper page break in TOC
  \protect\needspace{2\baselineskip}%
}
% finally, include the PDF; and cleardoublepage afterwards
\\includepdf[pages=-]{#4}
\\cleardoublepage
}

\\DeclareUnicodeCharacter{0399}{I} % due corruption in input! (got Ι U+0399 (greek capital letter iota) instead of I!)

\\usepackage{trace}
\\usepackage{printlen}


\\begin{document}

\\pagenumbering{roman}   % i, ii, iii, iv, ... unique page numbers

\\bookmarksetup{level=0}
\\bookmark[page=\theCurrentPage,view={XYZ}]{Preamble}
\\bookmarksetup{level=1}
\\bookmark[page=\theCurrentPage,view={XYZ}]{Cover}

\\title{\proctitle}
\\author{\procauthor}
\\date{\today}

\\maketitle
\\thispagestyle{empty} % do not show page numbers until TOC
\\pagestyle{empty}     % needed for the clear(double)pages
\\cleardoublepage

\\cfoot{\raisebox{\pageNumVpos}{\thepage}}
\\tocloftpagestyle{fancy}
\\pagestyle{fancy}
\\renewcommand{\contentsname}{TOC Contents/Conference Program} % Contents
\\bookmarksetup{level=0}
\\bookmark[page=\theCurrentPage,view={XYZ}]{\contentsname}

\\tableofcontents
\\cleardoublepage

\\cfoot{\raisebox{\pageNumVpos}{\uppercase{${conference_id}}-\thepage}}
\\pagenumbering{arabic}    % 1, 2, 3, 4, ... restarts counter too
\\pagestyle{fancy}       % needed for the clear(double)pages

\\bookmarksetup{level=1}

% \input{_test_paper_list.tex}
% \input{${texinputfilename}}
\\input{${texinputplainfilename}}

\\end{document}


__[ tmp_pre_end ]__




__END__





NOTE:

my $dlpercd = floor($dlperc/10); silently crashes perl!
Because floor is from use POSIX qw/floor/; !!
use int() instead!

############################
a.pl test:

my $name;
my %htmp = (
  confid => "100",
  ecidRA => "200200",
);

sub getExpandedDataSection {
  my ($datasectiontitle) = @_;
  print "getExpandedDataSection: Got $datasectiontitle $name \n";
  my $template = aPerlTest::->section_data ($datasectiontitle);
  my $ttemplate = $$template;
  print "XXXXXXXXX $$template";
  #~ $$template =~ s/(\${\w+})/${1}/eeg; # this DIRECTLY changes section data; use a copy variable!
  #~ $ttemplate =~ s/(\${\w+})/${1}/eeg && print "$1\n"; # copy var works; cannot match $htmp{confid}; with below now matches ${htmp{confid}} ${htmp{'confid'}}
  $ttemplate =~ s/(\${[\w{}']+})/${1}/eeg && print "$1\n"; #
  die if $@;                  # needed on /ee, not /e; "$EVAL_ERROR"
  return $ttemplate;
}

# if package Apltest;
$name = # testing comment
        "testing \t escapes \n variable";

my $sections = aPerlTest::->merged_section_data;
for my $filename (keys %$sections) {
  printf "== %s ==\n%s\n", $filename, aPerlTest::->section_data($filename);
}

my $expandTemplate = getExpandedDataSection("test_file");
print $expandTemplate;

$name = "SWITCHER";

$expandTemplate = getExpandedDataSection("test_file");
print $expandTemplate;

print "MMM ", join( " ", ($htmp{confid}, $htmp{'confid'}, ${htmp{confid}}, ${htmp{'confid'}}) ), "\n";



############################
saving old comments:


#~ $mech->dump_links();
# review_add.cgi?a=c089bf10bb54;revise=1525896;paper=1011411
# submission_info_show.cgi?number=1011413;a=c089bf10bb54
# submission_download.cgi?a=c089bf10bb54;submission=1011413 ...

my $absolute = 1; # true - but no difference from plain when read from file
# note since below accepts $fh - how STDOUT needs to be
#  referred to as \*STDOUT (via Mechanize.pm)
#~ $mech->dump_links(\*STDOUT, $absolute);

# not much in links collection - need to iterate through DOM

# to unpack (indent) fully html return
# xml_pp -l -s record -i _getEasyChair_review_all.txt


#~ my $tree= HTML::TreeBuilder::XPath->new;
#~ $tree->parse_file( "mypage.html");


# Returns either a Tree::XPathEngine::Literal, a Tree::XPathEngine::Boolean or a Tree::XPathEngine::Number object.
#~ my $nb = $htbx_tree->findvalue( '/html/body//div[@class="ct_tbl"]');
#~ print "ref: " . ref(\$nb) . " nb: $nb\n";

# Returns the values of the matching nodes as a list.
# only string is printed anyways:
# "the elements of the list are objects (with overloaded stringification) instead of plain strings."
#~ my @nb = $htbx_tree->findvalues( '/html/body//div[@class="ct_tbl"]');
#~ print "ref: " . ref(\@nb) . " nb: @nb\n";

# Returns a list of nodes found by $path. In scalar context returns an Tree::XPathEngine::NodeSet object.
#~ my $nb = $htbx_tree->findnodes( '/html/body//div[@class="ct_tbl"]');
# note here if @nb: ref: ARRAY nb: HTML::Element=HASH(0x94e7fd8)
# @nb->[0] == $nb[0] and is HTML::Element=HASH(0xa0c00a8)
#~ print "ref: " . ref(\@nb) . " nb: @nb " . $nb[0] . "\n";
# if $nb - no ref; and overloaded string printout
# $nb basically $nodeset
# ref(\@nb) - ARRAY; ref(\$nb) - scalar
#~ print "ref: " . ref(\$nb) . " nb: $nb \n";

# if $nb:



q^ # multi-line comment:
print "Parsing (HTML::DOM) content of $data_file ...\n";

my $dom_tree = new HTML::DOM; # empty tree

#~ $dom_tree->parse_file($filename); # in docs
# undocumented? Can't locate object method "parse" via package "HTML::DOM"
#~ $dom_tree->parse( $mech->content() );
# write: "parses the HTML code passed to it, adding it to the end of the document"
$dom_tree->write( $mech->content() );

# test printout - passes with ->write(...):
#~ print $dom_tree->innerHTML, "\n";

my @alldivs = $dom_tree->getElementsByTagName('div');
my $alldivslength = scalar @alldivs;
print "Found $alldivslength divs:\n";

foreach my $index (0..$#alldivs) {
  my $divelem = $alldivs[$index];
  my $de_cls = $divelem->attr('class') ? "class: ".$divelem->attr('class') : "class: NULL";
  print $index . " $divelem / " . $de_cls . "\n";
}
^ if 0; # end multiline comment




#foreach my $node ($nb->get_nodelist) {
#  # as_string spits out inner HTML
#  #~ print "FOUND ", XML::XPath::XMLParser::as_string($node),  "\n";
#  my $tnb = $node->findvalue( 'td/a[1]' ); # first a which has a td parent?
#  print "$tnb \n";
#}

# see also: HTML and Xpath - http://www.perlmonks.org/?node_id=722000


my @nodelist_rows = $nb->get_nodelist;
my %review_all_hash = ();
foreach my $rowindex (0..$#nodelist_rows) {
  my $trnode = $nodelist_rows[$rowindex];
  #~ my $tnb = $trnode->findvalue( 'td/a[1]' ); # three matches: row: 0 / 134formAntonio Rodà (Canazza)
  #~ my $tnb = $trnode->findvalue( 'td/a[1][1]' ); #same as above
  my $paperConfID = $trnode->findvalue( 'td[a][1]' ); # gets only the a in first (tr/)td/a: row: 0 / 134
  #~ my $papertitle = $trnode->findvalue( 'td[i]' ); # selects the (only) td with i, the whole td contents, but as text (i removed): row: 0 / 134 :: Johan Broekaert. BACH and WELL-TEMPERAMENTS / A proposal for an objective definition
  my $paperAuthorTitleTDnode = (($trnode->findnodes( 'td[i]' ))->get_nodelist)[0];
  #~ print XML::XPath::XMLParser::as_string( $paperAuthorTitleTDnode ); # <td>Johan Broekaert. <i>BACH and WELL-TEMPERAMENTS / A proposal for an objective definition</i></td> ## with newline at end!
  my $papertitle = $paperAuthorTitleTDnode->findvalue( 'i' ); # gets whats inside i in the TDnode: row: 0 / 134 :: BACH and WELL-TEMPERAMENTS / A proposal for an objective definition
  my $papertitleNode = (($paperAuthorTitleTDnode->findnodes( 'i' ))->get_nodelist)[0]; # get as node so we can detach it - which modifies tree
  $papertitleNode->detach();
  # after detach, $paperAuthorTitleTDnode->findvalue( 'i' ) is null
  # use self::* xpath to retrieve the current node value after the cutting using detach
  ## xpath self - Re: Difference between current(), node() and self ?? - http://www.stylusstudio.com/xsllist/200609/post40610.html
  my $paperauthor = $paperAuthorTitleTDnode->findvalue( 'self::*' );

  # download url from 3rd td/a
  # td[3] won't print anything if it only has a and img
  # td[3]/a/@href - submission_info_show.cgi?number=1018044;a=c089bf10bb54
  # td[4]/a/@href - submission_download.cgi?a=c089bf10bb54;submission=1018044
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
  #~ print "row: " . $rowindex . " / $paperEasyChairID / $paperConfID :: $paperauthor :: $papertitle :: $paperdlurl\n";
  #~ print "row: " . $rowindex . " :: ",  join(', ',values %hashPaperInfo) ,"\n";
  #~ print "row: " . $rowindex . " :: ",  %hashPaperInfo ,"\n";
  # print "@{[%hashPaperInfo]}" "Or use the interpolation trick from Recipe 1.10 to interpolate the hash as a list:"
  # print map { "$_ => $hash{$_}\n" } keys %hash; "Or use map to generate a list of strings:";  must have parens (map ..) when printing a comma-separated list.
  #~ print "row: " . $rowindex . " :: ",  (map { "$_ => $hashPaperInfo{$_} : " } keys %hashPaperInfo) ,"\n";
  # careful - must use %{} to dereference here..
  #~ my %htmp = %{$review_all_hash{ $paperConfID }};
  #~ print "row: " . $rowindex . " / $paperConfID :: ",  (map { "$_ => $hashPaperInfo{$_} : " } keys %htmp ) ,"\n";
}

# sample dl link:
# http://www.easychair.org/conferences/submission_download.cgi?a=c089bf10bb54;submission=958204
# "smc2012_submission_134.pdf"
# submission_download.cgi?a=c089bf10bb54;submission=958204

foreach my $rowindex (0..$#nodelist_rows) {
  # skip processing if on very first row - it's a header
  if ($rowindex == 0) { next; }

  my $trnode = $nodelist_rows[$rowindex];
  my $paperEasyChairID = $trnode->findvalue( '@id' ); # doublecheck - ecid from attribute id <tr id="r1010704">
  $paperEasyChairID = substr($paperEasyChairID, 1); # remove first character 'r'

  my $paperConfID = $trnode->findvalue( 'td[a][1]' ); # gets only the a in first (tr/)td/a: row: 0 / 134
  my $paperauthor = $trnode->findvalue( 'td[2]/span[@class="nauthors"]' );
  my $papertitle = $trnode->findvalue( 'td[2]/a[@class="title"]' );

  # do not want 3rd <td class="score" id="s1010704" - that is individual scores;
  # want average score, 4th: <td class="right" id="avg1010704">2.3</td>
  my $paperavgscore = $trnode->findvalue( 'td[4 and contains(@id,"avg")]' );
  my $paperstatus = $trnode->findvalue( 'td[5 and @class="dec"]/b' );

  my $ispaperaccept = 0;
  if ($paperstatus =~ m/accept/i) {
    $ispaperaccept = 1;
  }

  # great, now we have all necessary data
  # create here a new hash; save this data and incorporate the data from corresponding review_all_hash
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

  # must reference push here too - Perl Array of Hashes - http://www.perlmonks.org/?node_id=782969
  push @paper_status_array, \%htmp;

  #~ print "row: " . $rowindex . " / $paperConfID :: $paperauthor :: $papertitle :: $paperavgscore :: $paperstatus :: $paperEasyChairID :: ", $htmpra{'ecid'} , "\n"; # (map { "$_ => $htmpra{$_} : " } keys %htmpra ) ; $htmpra{'ecid'}
  #~ my %htmpb = %{$paper_status_array[$#paper_status_array]};
  #~ print "row: " . $rowindex . " :: ", (map { "$_ => $htmpb{$_} : " } keys %htmpb ) , "\n";
}


  #~ print "row: " . $rowindex . " :: ", (map { "$_ => $htmpb{$_} : " } keys %htmpb ) , "\n";
  #~ print "row: " . $rowindex . " :: ", $texentrystr , "\n";
#~ print $texinputstring;

# we have the content, we need to save the file
# check for directories first.

#~ use Term::UI; # UI made easy; naah
#~ use Term::ReadLine;


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

# multiple append heredoc with different quoting (to avoid too many backslash escapes)





############################
proper dl callback:

$| = 1; # flush output buffer - for prompt prints
my $dir = "proceedings/pdfs";

use WWW::Mechanize;
$mech = WWW::Mechanize->new();
$mech->agent_alias( 'Linux Mozilla' );
$mech->add_header(
"Connection" => "keep-alive",
"Keep-Alive" => "115");

$| = 1; # flush output buffer - for prompt prints
my $dir = "proceedings/pdfs";

use WWW::Mechanize;
my $mech = WWW::Mechanize->new();
$mech->agent_alias( 'Linux Mozilla' );
$mech->add_header(
"Connection" => "keep-alive",
"Keep-Alive" => "115");

my $dlurl = "http://ipv4.download.thinkbroadband.com/20MB.zip";

my $dlcbtotal =0;
my $loc_fname ="$dir/test.png";
my $mresponse;

my $dl_cbslow=0;
sub dl_callback
{
  #~ print "in\n";

  my( $data, $response, $proto ) = @_;
  print PDFFILE "$data"; # write data to file
  $dlcbtotal+= length($data);

  # slow down printout a bit - process only every 100th bump
  $dl_cbslow++;
  if ($dl_cbslow == 100) {
    $dl_cbslow = 0;
  } else { return; } # return, not next (no loop here): "Exiting subroutine via next"

  #~ print "--$dlcbtotal\n";
  my $size = $response->header('Content-Length');
  #~ print "->$size\n";
  my $dlperc = int(($dlcbtotal/$size)*100);
  #~ print "-=$dlperc\n";
  my $dlpercd = int($dlperc/10);
  my $dlpercdots = "."x$dlpercd ;
  $size =~ s/(\d{1,3}?)(?=(\d{3})+$)/$1,/g;
  my $sdlcbtotal = "" . $dlcbtotal;
  $sdlcbtotal =~ s/(\d{1,3}?)(?=(\d{3})+$)/$1,/g;

  my $dlrep = $loc_fname . " : " . $sdlcbtotal . " / " . $size . " ( $dlperc% ) " . $dlpercdots;
  print "$dlrep\r"; # print percent downloaded
}

my $pdfpath = "$loc_fname"; #"$pdfdir/$pdf_filename";
open (PDFFILE,">$pdfpath") or die "$!";
binmode PDFFILE;

$mresponse = $mech->get($dlurl, ":content_cb" => \&dl_callback);     #############
if (!$mresponse->is_success) {
  die "File unreachable $dlurl: ",  $mresponse->status_line, "\n";
}

print "\nDownloaded!!\n";


############################


Old version:

#!/usr/bin/env perl

# ./getEasyChairPDFs.pl (not: ./getEasyChairPDFs.pl :))

# sudo perl -MCPAN -e shell
# install WWW::Mechanize  # (takes a while - many dependencies)
# install IO::Prompt
# install HTML::TreeBuilder # for WWW::Mechanize: $mech->content( format => 'text' )
# install PerlIO::Util

use strict;
use warnings;
use utf8;
use charnames ':full';
binmode(STDOUT, ":utf8"); # to make sure files are saved in UTF-8, and no "Wide character in print" are raised; no dice?
binmode(STDIN, ":utf8"); #NO? have to be on the specific files! binmode DATA, ":utf8";
use WWW::Mechanize;
use IO::Prompt;
use IO::Handle;   # for the tee PerlIO thing
use PerlIO::Util; # for the tee PerlIO thing

my $mech;

sub printMechData {
  print "Got: " . $mech->title() . "\n";
  #~ print "   uri: " . $mech->uri() . "\n"; # here, seems uri == base ?! so not printing
  print "   base: " . $mech->base() . "\n\n";
}

sub pauseForAbit {
  # Sleep for 1100 milliseconds
  print("(pause...)\n");
  select(undef, undef, undef, 1.1);
}


# recreate empty log file and start logging
my $logfilename="_getEasyChairPDFs.log";
open(FH,'>'.$logfilename) or die "Can't create $logfilename: $!";
close(FH);
for (*STDOUT, *STDERR) {
  $_->autoflush; $_->push_layer(tee => ">>".$logfilename);
}


# sample dl link:
# http://www.easychair.org/conferences/submission_download.cgi?a=c089bf10bb54;submission=958204
# "smc2012_submission_134.pdf"

# defaut is https://www.easychair.org/account/signin.cgi
my $conference_id = "smc2012";                    # conference ID
my $ec_urlS = "https://www.easychair.org";   # EasyChair base URL, secure
my $ec_url = "http://www.easychair.org";   # EasyChair base URL (for download)
#~ my $signin_url = "https://www.easychair.org/account/signin.cgi?conf=smc2012";
my $signin_url = $ec_urlS . "/account/signin.cgi?conf=" . $conference_id;


print "Enter EasyChair User name [+ENTER]: ";
my $username = <STDIN>;
chomp($username); # remove trailing \n

print "Enter EasyChair ";
my $password = prompt('Password [+ENTER]: ', -e => '*');
#~ chomp($password); # remove trailing \n - no need with prompt

#~ print "Got $username $password\n";


my $tmpcont;    # temporary var for WWW::Mechanize content
my $mresponse;  # response (status) from WWW::Mechanize
# note - this implicitly also keeps cookies
$mech = WWW::Mechanize->new();
$mech->agent_alias( 'Linux Mozilla' );
$mech->add_header(
"Connection" => "keep-alive",
"Keep-Alive" => "115");


print("\n");
print("Going to access $signin_url\n");
$mresponse = $mech->get( $signin_url );
#~ $mech->follow_link( n => 1 ); # this is the one in the META tag; (redirect)
if (!$mresponse->is_success) {
    die "Page unreachable $signin_url: ",  $mresponse->status_line, "\n";
}
printMechData();


# note: <input value="smc2012" name="conf" type="hidden"/>
#~ print $mech->content();

# instead of going directly with field names;
# set username, password as sequential fields
# (username is visible first on page, password second)
$mech->set_visible( $username, $password );

pauseForAbit();

# argument is name of button on form <input name="Sign in"
# amazingly - click works to navigate; EVEN if
# this particular button's form calls login() JavaScript!
# (that's because login() is just true/false validator,
#  and so the form action otherwise remains on same page)
$mresponse = $mech->click( "Sign in" );
if (!$mresponse->is_success) {
    die "Page unreachable $signin_url: ",  $mresponse->status_line, "\n";
}

# after sign in, in browser goes to:
# http://www.easychair.org/conferences/login_registered.cgi?t=1423359.1rs40MpCKeJE0N67

# lovely, here in $mech->content(); getting:
# <title>SMC2012 Login for XX YY</title>
# but also:
# <p class="warning">EasyChair cannot recognize your browser so there is
                        #~ no guarantee that EasyChair will work correctly.</p><p class="warning">For more information please read the <a href="/conferences/help.cgi?art=55;a=c089bf10bb54">help page on Browser Compatibility</a>.</p><p>This session will expire after two hours of inaction.</p>

#~ print $mech->content();
$tmpcont = $mech->content();
printMechData();


# from here, need to go to:
# <tr><td onmouseover="Menu.show('menu3')" onmouseout="Menu.hide('menu3')" onclick="Menu.followLink('menu3','/conferences/review_all.cgi?a=c089bf10bb54')" title="reviews for all papers" class="tab" id="menu3">All papers</td></tr>
# but must extract from content, since it contains hash

# do a regex match to extract
my $webhash = "";

# if content matches this:
# (escape \? to exclude ? from match)
if($tmpcont =~ /\/conferences\/review_all.cgi\?([^']+)'/)
{
  $webhash = $1;
}


pauseForAbit();

# construct the main list page link (review_all.cgi)
#~ my $reviewall_url = "https://www.easychair.org/conferences/review_all.cgi?" . $webhash;
my $reviewall_url = $ec_urlS . "/conferences/review_all.cgi?" . $webhash;

print("\n");
print("Going to access $reviewall_url\n");
$mresponse = $mech->get( $reviewall_url );
if (!$mresponse->is_success) {
    die "Page unreachable $reviewall_url: ",  $mresponse->status_line, "\n";
}


$tmpcont = $mech->content();
printMechData();

#~ print $tmpcont;

# save content
# note Wide character in print - http://www.perlmonks.org/?node_id=613773
# s/[^[:ascii:]]+//g; # get rid of non-ASCII characters
# unicode chars survive even with the warning;
# but better to declare UTF-8 file handle - binmode STDOUT, ":utf8";
# see: http://ahinea.com/en/tech/perl-unicode-struggle.html
open (MYREVALLFILE, '>_getEasyChair_review_all.txt');
binmode MYREVALLFILE, ":utf8"; # to avoid "Wide.."
print MYREVALLFILE $tmpcont;    # Wide character in print ... line 151, <STDIN> line 1
close (MYREVALLFILE);



pauseForAbit();

# construct the status (acc/rej) list page link (status.cgi)
#~ my $statusall_url = "https://www.easychair.org/conferences/status.cgi?" . $webhash;
my $statusall_url = $ec_urlS . "/conferences/status.cgi?" . $webhash;

print("\n");
print("Going to access $statusall_url\n");
$mresponse = $mech->get( $statusall_url );
if (!$mresponse->is_success) {
    die "Page unreachable $statusall_url: ",  $mresponse->status_line, "\n";
}

$tmpcont = $mech->content();
printMechData();

# save content
open (MYSTTALLFILE, '>_getEasyChair_status_all.txt');
binmode MYSTTALLFILE, ":utf8"; # to avoid "Wide.."
print MYSTTALLFILE $tmpcont;    # Wide character in print ... line 176, <STDIN> line 1
close (MYSTTALLFILE);


# be nice - logout at end
#~ Menu.followLink('menu51','/account/signout.cgi?a=c089bf10bb54')

pauseForAbit();

my $signout_url = $ec_urlS . "/account/signout.cgi?" . $webhash;

print("\n");
print("Logging out - Going to access $signout_url\n");
$mresponse = $mech->get( $signout_url );
if (!$mresponse->is_success) {
    die "Page unreachable $signout_url: ",  $mresponse->status_line, "\n";
}

$tmpcont = $mech->content();
printMechData();

# save content
open (MYLOGOUTFILE, '>_getEasyChair_signout.txt');
print MYLOGOUTFILE $tmpcont;
close (MYLOGOUTFILE);


print "\nScript finished; bye!\n";




