#!/usr/bin/env perl

use File::Find;
use File::Basename;

#~ Re: Create a list of files in a directory (recursively) - nntp.perl.org - http://www.nntp.perl.org/group/perl.beginners/2008/06/msg101227.html

# http://code.google.com/p/jodconverter/downloads/detail?name=jodconverter-core-3.0-beta-4-dist.zip&can=2&q=

my @all_file_names;
#~ my $OO="/media/nonos/ebin/OOO-opt/openoffice.org"; # add 3 where needed? uhh
#~ my $OO3="$OO"."3"; # add 3 where needed? uhh no ${OO} like bash
my $OOC="/media/nonos/ebin/jodconverter-core-3.0-beta-4/lib/jodconverter-core-3.0-beta-4.jar";


find sub {
  my $tag = "";
  #~ return if -d;
  if (-d) {
    $tag = "d";
  }
  else {
    $tag = "f";
  }
  #~ push @all_file_names, $File::Find::name;
  #~ chomp $File::Find::name;
  #~ my @tmpa = ();
  #~ push (@tmpa, $tag);
  #~ push (@tmpa, $File::Find::name);
  #~ push (@all_file_names, @tmpa);
  push @all_file_names, [ $tag, $File::Find::name ];
}, '/home/administrator/Desktop/SMC-Music_Program';

for my $path ( @all_file_names ) {
  #~ print "$path\n"; # only @$path works!
  my $dftype = @$path[0];
  my $dfpath = @$path[1];

  # eq for strings
  if ($dftype eq "d") {
    print "Dir: " . $dfpath . "\n";
  }
  elsif ($dftype eq "f") {
    my ($tfname,$tfpath,$tfsuffix) = fileparse($dfpath, qr/\.[^.]*/);

    # target:
    #~ my $tftarg = $tfpath . $path_separator . $tfname . ".txt";
    my $tftarg = "./tmpout.txt";
    #print "   : " . $tftarg . "\n";
    #~ print "Fil: " . " " . $tfsuffix. "\n";

    if($tfsuffix =~ m/(rtf|doc|pdf|txt)/i)
    {
      print "Fil: " . $tfsuffix . " " . $tfname.$tfsuffix. "\n";
      my $tcmd = "";

      if($tfsuffix =~ m/(rtf|doc)/i)
      {
        # multiline string - lineending must be escaped for perl
        # but gets retained in the string
        # also quotes in Perl - http://www.perlmonks.org/?node_id=401006
        # $OO3 is variable - separate like in bash
        # this is bad for orig ooo3 (http://superuser.com/a/170073):
        #~ $OO/ure;$OO/ure/bin;
        #~ ${OO}3/program/classes/jurt.jar;\
        #~ ${OO}3/program/classes/ridl.jar;\
        #~ ${OO}3/program/classes/sandbox.jar;\
        #~ ${OO}3/program/classes/unoil.jar;\
        #~ ${OO}3/program/classes/juh.jar" \
        # sandbox.jar also cannot be found
        # damn it, DocumentClass is an example, and it needs to be compiled !

        #~ $tcmd = qq(java -classpath ".;./bin;\
#~ $OO/ure;$OO/ure/bin;$OO/share/java;$OO/basis3.3/program/classes;
#~ ${OO}/ure/share/java/jurt.jar;\
#~ ${OO}/ure/share/java/ridl.jar;\
#~ ${OO}/ure/share/java/sandbox.jar;\
#~ ${OO}/basis3.3/program/classes/unoil.jar;\
#~ ${OO}/ure/share/java/juh.jar" \
  #~ DocumentSaver "uno:socket,host=localhost,port=8100;urp;StarOffice.ServiceManager"  file://$dfpath file://$tftarg);
        $tcmd = qq(java -jar "$OOC" "$dfpath" "$tftarg" 2>/dev/null) ;
      } elsif ($tfsuffix =~ m/(pdf)/i) {
        $tcmd = qq(pdftotext "$dfpath" "$tftarg");
      } elsif ($tfsuffix =~ m/(txt)/i) {
        $tcmd = qq(cat "$dfpath" > "$tftarg");
      }
      $tcmd =~ s/\R//g; # clean linebreaks?
      print $tcmd . "\n";
      #~ my $result = `$tcmd 2>&1`;
      #~ print $result . "\n";
      system($tcmd);
      my $result = `cat "$tftarg"`;
      print $result . "\n";

    };
  }
}



