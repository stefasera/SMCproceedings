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

# extract the field names for the first encountered bib entry, then compare the fields of all other bib entries to check if they are the same/consistent (if not, output info)

# note about set difference:
# >>> a = ["a", "b", "c", "d"]
# >>> b = ["a", "b", "c", "d", "e"]
# >>> c = ["a", "b", "c"]
# >>> print(set(a)-set(b))
# set()
# >>> print(set(b)-set(a))
# {'e'}
# >>> print(set(a)-set(c))
# {'d'}
# >>>
# >>> print(not(set(a)-set(b)))
# True
# >>> print(not(set(b)-set(a)))
# False

def getsetdiff(x,y):
  setdiff = set(x) - set(y)
  if not(setdiff):
    setdiff = set(y) - set(x)
    setdiff.add("minus")
  return setdiff

# >>> getsetdiff(a,b)
# {'e', 'minus'}
# >>> getsetdiff(b,a)
# {'e'}


# get list of immediate child subdirs SO:973473 :
subdirs = sorted( next(os.walk(dir_data))[1] ) #ok
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
referencefields = []
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
    if not(referencefields): # extract the reference fields - no need to compare with oneself
      referencefields = list(confpaperbibentry.keys())
      pprint.pprint(referencefields)
    else: # compare this one with the reference fields
      thisentryfields = list(confpaperbibentry.keys())
      # compare as sets, SO:8866652; set difference SO:17624407
      if not(set(thisentryfields) == set(referencefields)):
        setdiff = set(thisentryfields) - set(referencefields)
        print("%d/%d"%(icpbe+1, confbiblen) + " OOOPS: " + pprint.pformat(setdiff))

print("\nDone.")
