#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, sys
import re

import lxml.html as LH #from lxml import html
from lxml import etree
import requests
import bibtexparser
from bibtexparser.bwriter import BibTexWriter
from bibtexparser.bibdatabase import BibDatabase
from bibtexparser.customization import convert_to_unicode
from bibtexparser.bparser import BibTexParser
import subprocess
import regex # sudo pip2/3 install regex # for detecting unicode capital letters
# Install PyPi regex module and use \p{Lu} class .... \p{Ll} is the category of lowercase letters, while \p{L} comprises all the characters in one of the "Letter" categories (Letter, uppercase; Letter, lowercase; Letter, titlecase; Letter, modifier; and Letter, other).
import inspect, pprint

url_base_smc = 'http://smcnetwork.org/resources/'
url_smc = url_base_smc + 'smc_papers'
dir_data = "_DATA_"

buf_arg = 0
if sys.version_info[0] == 3:
  os.environ['PYTHONUNBUFFERED'] = '1'
  buf_arg = 1
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buf_arg)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buf_arg)

# add field confurl to all bibs with conference URL

print("Getting SMC conferences list from %s ..."%(url_smc))
page = requests.get(url_smc)
tree = LH.fromstring(page.content)
conferences = tree.xpath('//div[@class="content"]/blockquote/ul/li/a')
tree.make_links_absolute(base_url=url_base_smc)
conflinks = []
for conf in conferences:
  conflinks.append(conf.attrib['href'])

print("Starting subdirs...")
# get list of immediate child subdirs SO:973473 :
subdirs = sorted( next(os.walk(dir_data))[1] ) #ok
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
# homogenize_fields: Sanitize BibTeX field names, for example change `url` to `link` etc.
tbparser = BibTexParser()
tbparser.homogenize_fields = False  # no dice
tbparser.alt_dict['url'] = 'url'    # this finally prevents change 'url' to 'link'
for isd, subdir in enumerate(subdirs):
  bibfile = os.path.join(dir_data, subdir, "%s.bib"%(subdir))
  print((bibfile, os.path.isfile(bibfile)))
  with open(bibfile) as bibtex_file:
    bibtex_str = bibtex_file.read()
  bib_database = bibtexparser.loads(bibtex_str, tbparser)
  #pprint.pprint(bib_database.entries) # already here,replaces 'url' with 'link'
  confbiblen = len(bib_database.entries)
  thisconfurl = conflinks[isd]
  print(thisconfurl)
  for icpbe, confpaperbibentry in enumerate(bib_database.entries):
    confpaperbibentry['urlconf'] = thisconfurl
    bib_database.entries[icpbe] = confpaperbibentry
  with open(bibfile, 'w') as thebibfile:
    bibtex_str = bibtexparser.dumps(bib_database)
    if sys.version_info[0]<3: # python 2
      thebibfile.write(bibtex_str.encode('utf8'))
    else: #python 3
      thebibfile.write(bibtex_str)

print("\nDone.")
