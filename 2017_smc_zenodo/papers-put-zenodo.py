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
ACCESS_TOKEN = "GUudIg6kR1ETIdBVQcAT9U68nebJhPUfjdGR2RqGLtLdFODMdbcy4WvF3w7P" # PersonalNoPublish
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
print("Status: %d"%(r.status_code))

ts_start = datetime.now()
print("Traversing all .bib directories, uploading all papers (%s)..."%(ts_start.strftime("%Y-%m-%d %H:%M:%S")))

# get list of immediate child subdirs SO:973473 :
# we'd want to upload here from oldest to newest - so we'd like to sort this in reverse
subdirs = sorted( next(os.walk(dir_data))[1] , reverse=True ) #ok
#~ pprint.pprint(subdirs)
# 02_SMC Conference 2015:044/74: orig 'G. Presti and D.A. Mauro and G. Haus' ->  _DATA_/02_SMC\ Conference\ 2015/smc_2015_044.pdf
# homogenize_fields: Sanitize BibTeX field names, for example change `url` to `link` etc.
tbparser = BibTexParser()
tbparser.homogenize_fields = False  # no dice
tbparser.alt_dict['url'] = 'url'    # this finally prevents change 'url' to 'link'
headers = {"Content-Type": "application/json"}
monthdict = { "May": "05", "July": "07", "August": "08", "September": "09", "October": "10", "November": "11" }
patremoveparensacro = re.compile(r'\((.*)\)')
totalhandled = 0
for isd, subdir in enumerate(subdirs):
  bibfile = os.path.join(dir_data, subdir, "%s.bib"%(subdir))
  print((bibfile, os.path.isfile(bibfile)))
  with open(bibfile) as bibtex_file:
    bibtex_str = bibtex_file.read()
  bib_database = bibtexparser.loads(bibtex_str, tbparser)
  #pprint.pprint(bib_database.entries) # already here,replaces 'url' with 'link'
  confbiblen = len(bib_database.entries)
  #subdirconfyear = re.findall(r"\d{4}", subdir)[0]
  for icpbe, confpaperbibentry in enumerate(bib_database.entries):
    if confpaperbibentry['ID'] not in skip_ids:
      totalhandled += 1
      print("--- %04d ---------------------( %s )"%(totalhandled, datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
      # prepare files, if available:
      filedata, files = {}, {}
      locpdffile = confpaperbibentry['file']
      if ".pdf" in locpdffile:
        locpdffilepath = os.path.join(dir_data, subdir, locpdffile) # local path via dir_data
        filedata = {'filename': locpdffile}
        files = {'file': open(locpdffilepath, 'rb')}
      pprint(filedata)
      pprint(files)
      confyear = confpaperbibentry['year']
      monthparts = confpaperbibentry['month'].split("-")
      monthdateone, monthdatetwo = "", ""
      mdtwoparts = monthparts[1].split(" ")
      monthdatetwo = "%s-%s-%s"%(confyear, monthdict[mdtwoparts[1]], "%02d"%(int(mdtwoparts[0])) ) # ISO8601 format (YYYY-MM-DD).
      if " " in monthparts[0]:
        # there is month in the dateone, extract in
        mdoneparts = monthparts[0].split(" ")
        monthdateone = "%s-%s-%s"%(confyear, monthdict[mdoneparts[1]], "%02d"%(int(mdoneparts[0])) ) # ISO8601 format (YYYY-MM-DD).
      else:
        monthdateone = "%s-%s-%s"%(confyear, monthdict[mdtwoparts[1]], "%02d"%(int(monthparts[0])) )
      #~ print(confpaperbibentry['month'], monthdateone, monthdatetwo) # 31 August-3 September 2016-08-31 2016-09-03
      authorsstrlist = confpaperbibentry['author'].split(" and ")
      authorsdictlist = []
      for sauthor in authorsstrlist:
        authorsdictlist.append( {'name': sauthor} )
      conftitle = confpaperbibentry['booktitle'].replace("Proceedings of the ", "").replace(",", "").replace("the ", "")
      confacro = patremoveparensacro.findall(conftitle)[0]
      conftitle = patremoveparensacro.sub('', conftitle).strip()
      relatedlist = [{'relation': 'isPartOf', 'identifier': confpaperbibentry['issn']}]
      if confpaperbibentry['isbn']:
        relatedlist.append({'relation': 'isPartOf', 'identifier': confpaperbibentry['isbn']})
      papermetadata = {
        'metadata': {
          'title': confpaperbibentry['title'],
          'upload_type': 'publication',
          'publication_type': 'conferencepaper',
          # Date of publication in ISO8601 format (YYYY-MM-DD). Defaults to current date./
          # LAST DATE OF CONFERENCE? Nope, https://zenodo.org/record/42701 uses the first!
          'publication_date': monthdateone,
          # Abstract or description for deposition - leave abstracts for later?
          #'description': 'This is my first upload',
          'description': '(Abstract to follow)',
          # The creators/authors of the deposition
          #'creators': [{'name': 'Doe, John',
          #        'affiliation': 'Zenodo'}]
          'creators': authorsdictlist,
          # The contributors of the deposition (e.g. editors, data curators, etc.).
          #'contributors': [{'name':'Doe, John',
          #          'affiliation': 'Zenodo',
          #          'type': 'Editor'}],
          # Title of conference (e.g. 20th International Conference on Computing in High Energy and Nuclear Physics).
          'conference_title': conftitle,
          # Acronym of conference (e.g. CHEP'13).
          'conference_acronym': confacro,
          # Dates of conference (e.g. 14-18 October 2013). Conference title or acronym must also be specified if this field is specified.
          'conference_dates': confpaperbibentry['month'],
          'conference_place': confpaperbibentry['venue'],
          'conference_url': confpaperbibentry['urlconf'],
          # Persistent identifiers of related publications and datasets. Supported identifiers include: DOI, Handle, ARK, PURL, ISSN, ISBN, PubMed ID ... Note the identifier type (e.g. DOI) is automatically detected, and used to validate and normalize the identifier into a standard form.
          # ISSN, ISBN - isPartOf is used https://zenodo.org/record/167134
          'related_identifiers': relatedlist, #, {'relation': 'cites', 'identifier':'https://doi.org/10.1234/bar'}],
          # List of communities you wish the deposition to appear. The owner of the community will be notified, and can either accept or reject your request. Each array element is an object with the attributes: * identifier: Community identifier
          'communities': [{'identifier':'smc'}]
        }
      }
      if confpaperbibentry['editor']:
        editorstrlist = confpaperbibentry['editor'].split(" and ")
        editorsdictlist = []
        for seditor in editorstrlist:
          editorsdictlist.append( {'name': seditor, 'type': 'Editor'} )
        papermetadata['metadata']['contributors'] = editorsdictlist
      pprint(papermetadata)
      print("Create a new empty upload...")
      r = requests.post('https://zenodo.org/api/deposit/depositions',
                        params={'access_token': ACCESS_TOKEN}, json={},
                        headers=headers)
      print(r.status_code)
      deposition_id = r.json()['id']
      print("... got record id %s"%(deposition_id))
      print("Doing metadata upload...")
      r = requests.put('https://zenodo.org/api/deposit/depositions/%s' % deposition_id,
                       params={'access_token': ACCESS_TOKEN}, data=json.dumps(papermetadata),
                       headers=headers)
      print( r.status_code )
      #~ pprint(r.json()) # tons of stuff
      if ".pdf" not in locpdffile:
        print("Skip file upload (only metadata)")
      else:
        print("Doing file upload '%s'..."%(locpdffile))
        r = requests.post('https://zenodo.org/api/deposit/depositions/%s/files' % deposition_id,
                          params={'access_token': ACCESS_TOKEN}, data=filedata,
                          files=files)
        # apparently, print( (r.status_code, r.json()) ) caused tracebacks below? separately, it passes?
        print( r.status_code )
      # DO NOT PUBLISH THIS ENTRY AT END HERE - ELSE CANNOT CHANGE OR DELETE IT ANYMORE!


ts_end = datetime.now()
print("Done; start: %s ; end: %s ; duration: %s"%(ts_start.strftime("%Y-%m-%d %H:%M:%S"), ts_end.strftime("%Y-%m-%d %H:%M:%S"), str(ts_end-ts_start)))
