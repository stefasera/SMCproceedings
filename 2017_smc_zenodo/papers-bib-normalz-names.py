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
# Install PyPi regex module and use \p{Lu} class .... \p{Ll} is the category of lowercase letters, while \p{L} comprises all the characters in one of the "Letter" categories (Letter, uppercase; Letter, lowercase; Letter, titlecase; Letter, modifier; and Letter, other).
import inspect, pprint

dir_data = "_DATA_"

buf_arg = 0
if sys.version_info[0] == 3:
  os.environ['PYTHONUNBUFFERED'] = '1'
  buf_arg = 1
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buf_arg)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buf_arg)

# normalize bibtex names - make all First Last instead of Last, First
# also: https://tex.stackexchange.com/questions/354293/normalize-authors-names-in-bib-file

# get list of immediate child subdirs SO:973473 :
subdirs = sorted( next(os.walk(dir_data))[1] ) #ok
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
numcommas = 0
# homogenize_fields: Sanitize BibTeX field names, for example change `url` to `link` etc.
tbparser = BibTexParser()
tbparser.homogenize_fields = False  # no dice
tbparser.alt_dict['url'] = 'url'    # this finally prevents change 'url' to 'link'
for subdir in subdirs:
  bibfile = os.path.join(dir_data, subdir, "%s.bib"%(subdir))
  print((bibfile, os.path.isfile(bibfile)))
  with open(bibfile) as bibtex_file:
    bibtex_str = bibtex_file.read()
  bib_database = bibtexparser.loads(bibtex_str, tbparser)
  #pprint.pprint(bib_database.entries) # already here,replaces 'url' with 'link'
  confbiblen = len(bib_database.entries)
  for icpbe, confpaperbibentry in enumerate(bib_database.entries):
    authstr = confpaperbibentry['author']
    if ("," in authstr):
      numcommas += 1
      report = "%d/%d: Comma present: '%s'"%(icpbe+1, confbiblen, authstr)
      authstrauthors = authstr.split(" and ")
      for ia, author in enumerate(authstrauthors):
        if ("," in author):
          authorparts = author.split(", ")
          # the first part [0] is last name, needs to become last
          # get and remove the first part, then append it as last
          lastname = authorparts.pop(0)
          authorparts.append(lastname)
          authorfirstlast = " ".join(authorparts)
          authstrauthors[ia] = authorfirstlast
      confpaperbibentry['author'] = " and ".join(authstrauthors)
      bib_database.entries[icpbe] = confpaperbibentry
      report += " -> '%s'"%(confpaperbibentry['author'])
    else:
      report = "%d/%d: OK"%(icpbe+1, confbiblen)
    if sys.version_info[0] == 3:
      print(report)
    else: #python 2
      print(report.encode('utf-8'))
  with open(bibfile, 'w') as thebibfile:
    bibtex_str = bibtexparser.dumps(bib_database)
    if sys.version_info[0]<3: # python 2
      thebibfile.write(bibtex_str.encode('utf8'))
    else: #python 3
      thebibfile.write(bibtex_str)

print("\nFound & converted total of %d author fields in format Last, First (with commas)."%(numcommas))
