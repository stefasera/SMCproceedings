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

# due to my mistake in after rename, the bibtex id/keys are not synced with numpaperorder; do that here

DOTHEMOVES = False # True # False

# get list of immediate child subdirs SO:973473 :
subdirs = sorted( next(os.walk(dir_data))[1] ) #ok
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
nummoved = 0
# homogenize_fields: Sanitize BibTeX field names, for example change `url` to `link` etc.
tbparser = BibTexParser()
tbparser.homogenize_fields = False  # no dice
tbparser.alt_dict['url'] = 'url'    # this finally prevents change 'url' to 'link'
for subdir in subdirs:
  bibsubdir = os.path.join(dir_data, subdir)
  bibfile = os.path.join(bibsubdir, "%s.bib"%(subdir))
  print((bibfile, os.path.isfile(bibfile)))
  with open(bibfile) as bibtex_file:
    bibtex_str = bibtex_file.read()
  bib_database = bibtexparser.loads(bibtex_str, tbparser)
  #pprint.pprint(bib_database.entries) # already here,replaces 'url' with 'link'
  confbiblen = len(bib_database.entries)
  havemoves = False
  for icpbe, confpaperbibentry in enumerate(bib_database.entries):
    oldid = confpaperbibentry['ID']
    year = confpaperbibentry['year']
    #~ newteststr = "smc:%s:%03d"%(year, icpbe+1) # or - the next line should do the same effect
    newteststr = "smc:%s:%s"%(year, confpaperbibentry['numpaperorder'])
    if oldid != newteststr:
      havemoves = True
      nummoved += 1
      # just change
      confpaperbibentry['ID'] = newteststr
      print(" ! %s -> %s"%( oldid, confpaperbibentry['ID'] ))
      # update
      bib_database.entries[icpbe] = confpaperbibentry
  if havemoves and DOTHEMOVES:
    with open(bibfile, 'w') as thebibfile:
      bibtex_str = bibtexparser.dumps(bib_database)
      if sys.version_info[0]<3: # python 2
        thebibfile.write(bibtex_str.encode('utf8'))
      else: #python 3
        thebibfile.write(bibtex_str)
    print("Rewrote %s."%(bibfile))

print("\nChanged %d bib entry id/keys."%(nummoved))
