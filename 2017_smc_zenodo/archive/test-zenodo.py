#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, sys
import re
import lxml.html as LH #from lxml import html
from lxml import etree
import json
import requests

url_base_zenodo = 'https://zenodo.org/'
url_base_zenodo_api = 'https://zenodo.org/api/.'
ACCESS_TOKEN = "__ACCESS__TOKEN__HERE__"

print("Accessing API...")
r = requests.get('https://zenodo.org/api/deposit/depositions',
                 params={'access_token': ACCESS_TOKEN})
print( (r.status_code, r.json()) )
# (200, [])
print(r.json()['message'])
exit()

# NOTE: here may have TypeError: request() got an unexpected keyword argument 'json'
#   request() got an unexpected keyword argument 'json' · Issue #61 · jeffwidman/bitbucket-issue-migration · GitHub   https://github.com/jeffwidman/bitbucket-issue-migration/issues/61
# "What version of requests are you using? POST'ing using the json kwarg requires >=2.4.2"
# apt-show-versions -r request : python-requests:all, python-requests-whl:all, python3-requests:all 2.2.1-1ubuntu0.3
# "I am not able to update it through pip, as its apt-get package is used by the ubuntu-desktop itself"
# apt-get remove wants to also remove a LOT of packages...
# "I got it working through this answer, installing the python-virtualenv package:"
# sudo apt-get install python-virtualenv
# which python3 -> /usr/bin/python3
# virtualenv -p /usr/bin/python3 py3env
# source py3env/bin/activate
# pip install requests # requests-2.18.4-py2.py3-none-any.whl
# https://stackoverflow.com/questions/13019942/why-cant-i-get-pip-install-lxml-to-work-within-a-virtualenv
# apt-get install libxml2-dev libxslt-dev
# pip install lxml
# "You can leave the virtualenv with deactivate"
# python is now at /path/to/here/py3env/bin/python
print("Next, let’s create a new empty upload")
headers = {"Content-Type": "application/json"}
r = requests.post('https://zenodo.org/api/deposit/depositions',
                  params={'access_token': ACCESS_TOKEN}, json={},
                  headers=headers)
print( (r.status_code, r.json()) )
# {
#   "created": "2016-06-15T16:10:03.319363+00:00",
#   "files": [],
#   "id": 1234,
#   "links": {
#     "discard": "https://zenodo.org/api/deposit/depositions/1234/actions/discard",
#     "edit": "https://zenodo.org/api/deposit/depositions/1234/actions/edit",
#     "files": "https://zenodo.org/api/deposit/depositions/1234/files",
#     "publish": "https://zenodo.org/api/deposit/depositions/1234/actions/publish",
#     "newversion": "https://zenodo.org/api/deposit/depositions/1234/actions/newversion",
#     "self": "https://zenodo.org/api/deposit/depositions/1234"
#   },
#   "metadata": {
#     "prereserve_doi": {
#       "doi": "10.5072/zenodo.1234",
#       "recid": 1234
#     }
#   },
#   "modified": "2016-06-15T16:10:03.319371+00:00",
#   "owner": 1,
#   "record_id": 1234,
#   "state": "unsubmitted",
#   "submitted": false,
#   "title": ""
# }

## (201, {'modified': '2017-08-26T11:17:46.444833+00:00', 'state': 'unsubmitted', 'created': '2017-08-26T11:17:46.444826+00:00', 'submitted': False, 'record_id': 849047, 'title': '', 'id': 849047, 'files': [], 'conceptrecid': '849046', 'links': {'edit': 'https://zenodo.org/api/deposit/depositions/849047/actions/edit', 'bucket': 'https://zenodo.org/api/files/89c20c98-5488-4d84-acc9-2070e0a37396', 'discard': 'https://zenodo.org/api/deposit/depositions/849047/actions/discard', 'publish': 'https://zenodo.org/api/deposit/depositions/849047/actions/publish', 'files': 'https://zenodo.org/api/deposit/depositions/849047/files', 'html': 'https://zenodo.org/deposit/849047', 'latest_draft_html': 'https://zenodo.org/deposit/849047', 'self': 'https://zenodo.org/api/deposit/depositions/849047', 'latest_draft': 'https://zenodo.org/api/deposit/depositions/849047'}, 'metadata': {'prereserve_doi': {'recid': 849047, 'doi': '10.5281/zenodo.849047'}}, 'owner': 34988})


print("Now, let’s upload a new file:")
print("# Get the deposition id from the previous response")
deposition_id = r.json()['id']
print("(do the upload)")
data = {'filename': 'smc_2004_001.pdf'}
files = {'file': open('/media/Data1/work/2017_smc_zenodo/_DATA_/13_SMC Conference 2004/smc_2004_001.pdf', 'rb')}
r = requests.post('https://zenodo.org/api/deposit/depositions/%s/files' % deposition_id,
                  params={'access_token': ACCESS_TOKEN}, data=data,
                  files=files)
# apparently, print( (r.status_code, r.json()) ) caused tracebacks below? separately, it passes?
print( r.status_code )
print( r.json() )
# {
#   "checksum": "2b70e04bb31f2656ce967dc07103297f",
#   "filename": "myfirstfile.csv",
#   "id": "eb78d50b-ecd4-407a-9520-dfc7a9d1ab2c",
#   "filesize": "27"
# }

## py3: Traceback (most recent call last):
##   File "archive/test-zenodo.py", line 77, in <module>
##     print( (r.status_code, r.json()) )
##   File "/media/Data1/work/2017_smc_zenodo/py3env/lib/python3.4/site-packages/requests/models.py", line 892, in json
##     return complexjson.loads(self.text, **kwargs)
##   File "/usr/lib/python3.4/json/__init__.py", line 318, in loads
##     return _default_decoder.decode(s)
##   File "/usr/lib/python3.4/json/decoder.py", line 343, in decode
##     obj, end = self.raw_decode(s, idx=_w(s, 0).end())
##   File "/usr/lib/python3.4/json/decoder.py", line 361, in raw_decode
##     raise ValueError(errmsg("Expecting value", s, err.value)) from None
## ValueError: Expecting value: line 1 column 1 (char 0)
# RuntimeError: Package 'json' must not be downloaded from pypi

## py2: Traceback (most recent call last):
##   File "archive/test-zenodo.py", line 81, in <module>
##     print( (r.status_code, r.json()) )
##   File "/media/Data1/work/2017_smc_zenodo/py2env/local/lib/python2.7/site-packages/requests/models.py", line 892, in json
##     return complexjson.loads(self.text, **kwargs)
##   File "/usr/lib/python2.7/json/__init__.py", line 338, in loads
##     return _default_decoder.decode(s)
##   File "/usr/lib/python2.7/json/decoder.py", line 366, in decode
##     obj, end = self.raw_decode(s, idx=_w(s, 0).end())
##   File "/usr/lib/python2.7/json/decoder.py", line 384, in raw_decode
##     raise ValueError("No JSON object could be decoded")
## ValueError: No JSON object could be decoded


print("Last thing missing, is just to add some metadata")
data = {
    'metadata': {
        'title': 'A PREGROUP GRAMMAR FOR CHORD SEQUENCES',
        'upload_type': 'publication',
        'publication_type': 'conferencepaper',
        # Date of publication in ISO8601 format (YYYY-MM-DD). Defaults to current date./
        # LAST DATE OF CONFERENCE? Nope, https://zenodo.org/record/42701 uses the first!
        'publication_date': '2004-10-20',
        # Abstract or description for deposition - leave abstracts for later?
        #'description': 'This is my first upload',
        'description': '(Abstract to follow)',
        # The creators/authors of the deposition
        #'creators': [{'name': 'Doe, John',
        #              'affiliation': 'Zenodo'}]
        'creators': [{'name': 'Richard G. Terrat',
                      'affiliation': ''}],
        # The contributors of the deposition (e.g. editors, data curators, etc.).
        #'contributors': [{'name':'Doe, John',
        #                  'affiliation': 'Zenodo',
        #                  'type': 'Editor'}],
        # Title of conference (e.g. 20th International Conference on Computing in High Energy and Nuclear Physics).
        'conference_title': '1st Sound and Music Computing Conference',
        # Acronym of conference (e.g. CHEP'13).
        'conference_acronym': 'SMC2004',
        # Dates of conference (e.g. 14-18 October 2013). Conference title or acronym must also be specified if this field is specified.
        'conference_dates': '20-22 October 2004',
        'conference_place': 'Paris, France',
        'conference_url': 'http://smcnetwork.org/resources/smc2004',
        # Persistent identifiers of related publications and datasets. Supported identifiers include: DOI, Handle, ARK, PURL, ISSN, ISBN, PubMed ID ... Note the identifier type (e.g. DOI) is automatically detected, and used to validate and normalize the identifier into a standard form.
        # ISSN, ISBN - isPartOf is used https://zenodo.org/record/167134
        'related_identifiers': [{'relation': 'isPartOf', 'identifier':'2518-3672'}], #, {'relation': 'cites', 'identifier':'https://doi.org/10.1234/bar'}],
        # List of communities you wish the deposition to appear. The owner of the community will be notified, and can either accept or reject your request. Each array element is an object with the attributes: * identifier: Community identifier
        'communities': [{'identifier':'smc'}]
    }
}
r = requests.put('https://zenodo.org/api/deposit/depositions/%s' % deposition_id,
                 params={'access_token': ACCESS_TOKEN}, data=json.dumps(data),
                 headers=headers)
print( (r.status_code, r.json()) )

# here may return:
# (400, {u'status': 400, u'message': u'Validation error.', u'errors': [{u'field': u'metadata.conference_url', u'message': u'Not a valid URL.'}, {u'field': u'metadata.description', u'message': u'Shorter than minimum length 3.'}]})
# (400, {u'status': 400, u'message': u'Validation error.', u'errors': [{u'field': u'metadata.description', u'message': u'Shorter than minimum length 3.'}]})
# (400, {u'status': 400, u'message': u'Validation error.', u'errors': [{u'field': u'metadata.description', u'message': u'Missing data for required field.'}]})


# Publish a deposition. Note, once a deposition is published, you can no longer delete it.
# (Delete an existing deposition file resource. Note, only deposition files for unpublished depositions may be deleted.)
# "Don’t execute this last step - it will put your test upload straight online."
#~ print("And we’re ready to publish")
#~ r = requests.post('https://zenodo.org/api/deposit/depositions/%s/actions/publish' % deposition_id,
                  #~ params={'access_token': ACCESS_TOKEN} )
#~ print( (r.status_code, r.json()) )
