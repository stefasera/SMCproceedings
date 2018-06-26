#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, sys
import re

import bibtexparser
from bibtexparser.bwriter import BibTexWriter
from bibtexparser.bibdatabase import BibDatabase
from bibtexparser.customization import convert_to_unicode
import subprocess
import regex # sudo pip2/3 install regex # for detecting unicode capital letters
# Install PyPi regex module and use \p{Lu} class .... \p{Ll} is the category of lowercase letters, while \p{L} comprises all the characters in one of the "Letter" categories (Letter, uppercase; Letter, lowercase; Letter, titlecase; Letter, modifier; and Letter, other).
import inspect, pprint

dir_data = "_DATA_"

buf_arg = 0
if sys.version_info[0] == 3:
  os.environ['PYTHONUNBUFFERED'] = '1'
  buf_arg = 1
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buf_arg)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buf_arg)

# get list of immediate child subdirs SO:973473 :
#~ subdirs = next(os.walk(dir_data))[1] # not sorted
#~ subdirs = [os.path.join(dir_data,o) for o in os.listdir(dir_data) if os.path.isdir(os.path.join(dir_data,o))] #not sorted
subdirs = sorted( next(os.walk(dir_data))[1] ) #ok
#~ pprint.pprint(subdirs)
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
patmatchcamelcase = regex.compile(r"\p{Ll}\p{Lu}\p{Ll}") # for use with findall
numproblema = 0
for subdir in subdirs:
  bibfile = os.path.join(dir_data, subdir, "%s.bib"%(subdir))
  print((bibfile, os.path.isfile(bibfile)))
  with open(bibfile) as bibtex_file:
    bibtex_str = bibtex_file.read()
  bib_database = bibtexparser.loads(bibtex_str)
  confbiblen = len(bib_database.entries)
  for confpaperbibentry in bib_database.entries:
    if (".pdf" in confpaperbibentry['urlpdf']):
      # get name
      authorstr_orig = confpaperbibentry['author']
      condition1 = "." in authorstr_orig
      condition2 = patmatchcamelcase.findall(authorstr_orig)
      if (condition1 or condition2): # have a dot or camelcase; get names (don't rely on pdfinfo author, extract from first page)
        numproblema += 1
        condstring = "C%s%s (%d)"%("1" if condition1 else "", "2" if condition2 else "", numproblema)
        report = "%s:%s/%d: %s orig '%s'"%(subdir,confpaperbibentry['numpaperorder'],confbiblen, condstring, authorstr_orig)
        if sys.version_info[0] == 3:
          print(report)
        else: #python 2
          print(report.encode('utf-8'))
        # 2>/dev/null to avoid the "Syntax Error: Expected the optional content group list, but wasn't able to find it, or it isn't an Array"? No dice, it is prob. printed to stdout
        # better search for "abstract", case insensitive, for stopping - for @, some have emails like that, but some have [at], some don't have emails at all
        pdfcmd = 'pdftotext -layout -f 1 -l 1 "%s" 2>&1 - | sed "/abstract/Iq"'%( os.path.join(dir_data, subdir, confpaperbibentry['file']))
        #~ pdfcmd = ['pdftotext', os.path.join(dir_data, subdir, confpaperbibentry['file']), "-", "|", "sed", "/@/q"]
        proc = subprocess.Popen(pdfcmd, stdout=subprocess.PIPE, shell=True)
        print(">>>>>>>>>>")
        if sys.version_info[0] == 3:
          pdfheading = proc.stdout.read()
          print(pdfheading.decode('utf-8'))
        else: #python 2
          pdfheading = proc.stdout.read().decode('utf-8')
          print(pdfheading.encode('utf-8'))
        print("<<<<<<<<<<")
      else:
        report = "%s:%s/%d: OK"%(subdir,confpaperbibentry['numpaperorder'],confbiblen)
        if sys.version_info[0] == 3:
          print(report)
        else: #python 2
          print(report.encode('utf-8'))
      print("----------------")
print("\nFound total of %d problematic author fields."%(numproblema))
