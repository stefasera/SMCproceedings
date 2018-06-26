#!/usr/bin/python
# -*- coding: utf-8 -*-

# note, if you cannot install newer requests, this should run in virtualenv (source py3env/bin/activate ...)!

import os, sys
import re
import lxml.html as LH #from lxml import html
from lxml import etree
import json
import requests
# sudo apt-get install python3-pip
# sudo -H pip2 install bibtexparser
# sudo -H pip3 install bibtexparser
import bibtexparser
from bibtexparser.bwriter import BibTexWriter
from bibtexparser.bibdatabase import BibDatabase
from bibtexparser.customization import convert_to_unicode
from bibtexparser.bparser import BibTexParser
if sys.version_info[0] == 3:
  from urllib.parse import urlsplit, urlunsplit
else:
  from urlparse import urlsplit, urlunsplit
from datetime import datetime
import inspect
from pprint import pprint, pformat

url_base_zenodo = 'https://zenodo.org/'
url_base_zenodo_api = 'https://zenodo.org/api/.'
dir_data = "_DATA_"
ACCESS_TOKEN = "GUudIg6kR1ETIdBVQcAT9U68nebJhPUfjdGR2RqGLtLdFODMdbcy4WvF3w7P" # PersonalNoPublish; but must have the Publish API key here, in order to publish!
# the IDs to be skipped in upload:
skip_ids = [ "smc:2004:001" ]

# SO:107705; unbuffer for both python 2 and 3; to have this work: python papers-get-smc.py 2>&1 | tee _get.log
buf_arg = 0
if sys.version_info[0] == 3:
  os.environ['PYTHONUNBUFFERED'] = '1'
  buf_arg = 1
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buf_arg)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buf_arg)

# Fix Python 2.x.
try: input = raw_input
except NameError: pass


print("Accessing API...")
r = requests.get('https://zenodo.org/api/deposit/depositions',
                 params={'access_token': ACCESS_TOKEN})
#~ print( (r.status_code, r.json()) )
# (200, []) - but only if empty; else it seems to dump a list of all uploads!
# (200, [{'doi_url': 'https://doi.org/10.5281/zenodo.849079', 'doi': '10.5281/zenodo.849079', 'title': 'A Pregroup Grammar for Chord Sequences', 'conceptdoi': '10.5281/zenodo.849078', 'state': 'inprogress', 'links': {'discard': 'https://zenodo.org/api/deposit/depositions/849079/actions/discard', 'doi': 'https://doi.org/10.5281/zenodo.849079', 'record': 'https://zenodo.org/api/records/849079', 'conceptdoi': 'https://doi.org/10.5281/zenodo.849078', 'publish': 'https://zenodo.org/api/deposit/depositions/849079/actions/publish', 'edit': 'https://zenodo.org/api/deposit/depositions/849079/actions/edit', 'self': 'https://zenodo.org/api/deposit/depositions/849079', 'conceptbadge': 'https://zenodo.org/badge/doi/10.5281/zenodo.849078.svg', 'record_html': 'https://zenodo.org/record/849079', 'badge': 'https://zenodo.org/badge/doi/10.5281/zenodo.849079.svg', 'latest_html': 'https://zenodo.org/record/849079', 'files': 'https://zenodo.org/api/deposit/depositions/849079/files', 'latest': 'https://zenodo.org/api/records/849079', 'html': 'https://zenodo.org/deposit/849079', 'bucket': 'https://zenodo.org/api/files/e99e4235-2549-42f0-9759-a2505a90c9e5'}, 'metadata': {'prereserve_doi': {'recid': 849079, 'doi': '10.5281/zenodo.849079'}, 'doi': '10.5281/zenodo.849079', 'license': 'CC-BY-4.0', 'title': 'A Pregroup Grammar for Chord Sequences', 'access_right': 'open', 'upload_type': 'publication', 'description': '<p>(Abstract to follow)</p>', 'conference_dates': '20-22 October 2004', 'publication_date': '2004-10-20', 'conference_title': '1st Sound and Music Computing Conference', 'related_identifiers': [{'identifier': '2518-3672', 'relation': 'isPartOf', 'scheme': 'issn'}], 'conference_place': 'Paris, France', 'communities': [{'identifier': 'smc'}], 'creators': [{'name': 'Richard G. Terrat'}], 'publication_type': 'conferencepaper', 'conference_url': 'http://smcnetwork.org/resources/smc2004', 'conference_acronym': 'SMC2004'}, 'id': 849079, 'record_id': 849079, 'submitted': True, 'created': '2017-08-26T11:52:21.070333', 'conceptrecid': '849078', 'modified': '2017-08-26T12:11:33.153247', 'owner': 34988}])
print( "Status: %d; length:%d"%( r.status_code, len(r.json()) ) ) # just 10 entries, even if I have 1050!

# so, either I have to somehow retrieve an array of all my 1050 uploads under my account; or I'd have to harvest IDs from the _put.log, and then set them to published manually

ts_start = datetime.now()

# this is how one would retrieve all of the depositions (same as previously?) http://developers.zenodo.org/#list:
# ah - this requests by default does pagination, so by default, it returns only 10 results;
# there are 'page' (page number) and 'size' (Number of results to return per page); so can just set size to large enough to retrieve all
# also there is 'status' (Filter result based on deposit status (either `draft` or `published`))
r = requests.get('https://zenodo.org/api/deposit/depositions',
                  params={'size': 2000,
                          #~ 'status': 'draft',
                          'access_token': ACCESS_TOKEN})
print( "Status: %d; length:%d"%( r.status_code, len(r.json()) ) )
#~ print(r.json())
# NOTE: 'status' (`draft` or `published`) is only used in the above API request!
# in the actual entry, we only have 'state' (`inprogress`: Deposition metadata can be updated. If deposition is also unsubmitted (see submitted) files can be updated as well., `done`: Deposition has been published.,  `error: Deposition is in an error state - contact our support.`); and 'submitted' (True of deposition has been published, False otherwise);
# also, the ['id'] can be parsed as either int (%d) or string (%s) in format string!
# note that after first publish (by mistake in script), the statuses are:
## 0000: id '849079' state 'inprogress', submitted 'True', title 'A Pregroup Grammar for ...'
## 0001: id '851327' state 'unsubmitted', submitted 'False', title 'Expressive Humanoid ...'
# then, also can have:
## 0000: id '851325' state 'done', submitted 'True', title 'Smart Instruments:

for ix, item in enumerate(r.json()):
  deposition_id = item['id']
  print("%04d: id '%d' state '%s', submitted '%s', title '%s'"%(ix, deposition_id, item['state'], item['submitted'], item['title']))
  if not(item['submitted']):
    print(" - sending API request to publish...")
    r = requests.post('https://zenodo.org/api/deposit/depositions/%s/actions/publish' % deposition_id,
                      params={'access_token': ACCESS_TOKEN} )
    print( (r.status_code, r.json()) )

ts_end = datetime.now()
print("Done; start: %s ; end: %s ; duration: %s"%(ts_start.strftime("%Y-%m-%d %H:%M:%S"), ts_end.strftime("%Y-%m-%d %H:%M:%S"), str(ts_end-ts_start)))

# after once going throughall the 1050 uploads, I have: Drafts 8, Published 1042 -> probably those are those with the missing PDFs...
