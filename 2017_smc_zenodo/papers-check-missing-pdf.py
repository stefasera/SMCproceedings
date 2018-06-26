#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, sys
import re

import bibtexparser
from bibtexparser.bwriter import BibTexWriter
from bibtexparser.bibdatabase import BibDatabase
from bibtexparser.customization import convert_to_unicode
from bibtexparser.bparser import BibTexParser
import subprocess
import regex # sudo pip2/3 install regex # for detecting unicode capital letters
import inspect, pprint

dir_data = "_DATA_"

buf_arg = 0
if sys.version_info[0] == 3:
  os.environ['PYTHONUNBUFFERED'] = '1'
  buf_arg = 1
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buf_arg)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buf_arg)

# check for missing PDFs (via 'file' field); if missing, output paper title and authors

# get list of immediate child subdirs SO:973473 :
subdirs = sorted( next(os.walk(dir_data))[1] ) #ok
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
nummissing = 0
# homogenize_fields: Sanitize BibTeX field names, for example change `url` to `link` etc.
tbparser = BibTexParser()
tbparser.homogenize_fields = False  # no dice
tbparser.alt_dict['url'] = 'url'    # this finally prevents change 'url' to 'link'
replist = []
for subdir in subdirs:
  bibfile = os.path.join(dir_data, subdir, "%s.bib"%(subdir))
  print((bibfile, os.path.isfile(bibfile)))
  with open(bibfile) as bibtex_file:
    bibtex_str = bibtex_file.read()
  bib_database = bibtexparser.loads(bibtex_str, tbparser)
  #pprint.pprint(bib_database.entries) # already here,replaces 'url' with 'link'
  confbiblen = len(bib_database.entries)
  conffoundpdf = 0
  confmisspdf = 0
  for icpbe, confpaperbibentry in enumerate(bib_database.entries):
    filestr = confpaperbibentry['file']
    if not(".pdf" in filestr):
      nummissing += 1
      confmisspdf += 1
      report = "%d/%d: PDF missing\n title '%s'\n authr '%s'"%(icpbe+1, confbiblen, confpaperbibentry['title'], confpaperbibentry['author'])
      if sys.version_info[0] == 3:
        print(report)
      else: #python 2
        print(report.encode('utf-8'))
    else:
      conffoundpdf += 1
  replist.append( [subdir, confbiblen, conffoundpdf, confmisspdf] )

print("\nFound %d missing pdfs."%(nummissing))
print("\nReport: existing entries (found/missing):")

repstr = ""
totexist, totfound, totmissing = 0, 0, 0
for thisreport in replist:
  repstr += "%s: %d (%d/%d)\n"%(thisreport[0], thisreport[1], thisreport[2], thisreport[3])
  totexist += thisreport[1]
  totfound += thisreport[2]
  totmissing += thisreport[3]
if sys.version_info[0] == 3:
  print(repstr)
else: #python 2
  print(repstr.encode('utf-8'))
print("Totals: %d (%d/%d)"%(totexist, totfound, totmissing))