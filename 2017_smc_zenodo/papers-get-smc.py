#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, sys
import re
import lxml.html as LH #from lxml import html
from lxml import etree
import requests
# sudo apt-get install python3-pip
# sudo -H pip2 install bibtexparser
# sudo -H pip3 install bibtexparser
import bibtexparser
from bibtexparser.bwriter import BibTexWriter
from bibtexparser.bibdatabase import BibDatabase
from bibtexparser.customization import convert_to_unicode
if sys.version_info[0] == 3:
  from urllib.parse import urlsplit, urlunsplit
else:
  from urlparse import urlsplit, urlunsplit
from titlecase import titlecase
from datetime import datetime
import inspect, pprint


#~ url_smc = 'http://smcnetwork.org/resources/smc_papers'
url_base_smc = 'http://smcnetwork.org/resources/'
url_smc = url_base_smc + 'smc_papers'
dir_data = "_DATA_"
logfile = open("_get.log",'w')

# SO:107705; unbuffer for both python 2 and 3; to have this work: python papers-get-smc.py 2>&1 | tee _get.log
buf_arg = 0
if sys.version_info[0] == 3:
  os.environ['PYTHONUNBUFFERED'] = '1'
  buf_arg = 1
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buf_arg)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buf_arg)

def printlog(formalarg):
  #logfile.write(formalarg + '\n') # nope, capture log from bash with 2>&1 for errors
  print(formalarg)

# Fix Python 2.x.
try: input = raw_input
except NameError: pass


if not os.path.exists(dir_data):
  os.makedirs(dir_data)
  printlog("Created " + dir_data + " directory")
else:
  printlog("Directory " + dir_data + " exists.")

printlog("Getting SMC conferences list from %s ..."%(url_smc))
page = requests.get(url_smc)
tree = LH.fromstring(page.content)
conferences = tree.xpath('//div[@class="content"]/blockquote/ul/li/a')
# some of the links here are relative - so make them absolute:
#~ print(tree.base_url) # None
tree.make_links_absolute(base_url=url_base_smc)
conflinks = []
confcount = 0 # to prepend for sorting purposes
for conf in conferences:
  confcount += 1
  conftitle = conf.text_content()
  # note, the year is encoded in conftitle (only 4-digit number occuring)
  confyear = re.findall(r"\d{4}", conftitle)[0]
  # last entry in conflinks is id for fast lookup to save the addition later
  # later, to each entry add: found papers, and found PDFs (so make it a list, not a tuple)
  conflinks.append( ['%02d_'%(confcount) + conftitle, conf.attrib['href'], confyear, confcount-1] )
  #~ print(inspect.getmembers(conf))
printlog(pprint.pformat(conflinks))
#with open('conflinks_smc.txt', 'w') as file_handler:
#  #file_handler.writelines(conflinks) # cannot
#  #pickle.dump(conflinks, file_handler) # import pickle; has extra
#  file_handler.writelines(pprint.pformat(conflinks)) # nice


printlog("Parse online data to bib files? [y/n]")
choice = input().lower()
doBibFiles = False
if choice == "y":
  doBibFiles = True

##########

if doBibFiles:
  ts_bibpartstart = datetime.now()

  printlog("\nDownloading conferences...\n")
  allconfsbibdicts = []
  allconfsbibdbs = []
  bibwriter = BibTexWriter()
  bibwriter.indent = '  '     # indent entries with 2 spaces instead of one
  confissn = "2518-3672" # hardcoded, is given on url_smc

  #~ for conflink in [ conflinks[0] ]: # recast to array to properly address tuple element in truncated list
  #~ for conflink in [conflinks[3],conflinks[9],conflinks[2]]:
  for conflink in conflinks:
    printlog("\n *****")
    conflink_dir = os.path.join(dir_data, conflink[0])
    if not os.path.exists(conflink_dir):
      os.makedirs(conflink_dir)
      printlog("Created '" + conflink_dir + "' directory")
    else:
      printlog("Directory '" + conflink_dir + "' exists.")
    conflink_url = conflink[1]
    conflink_year = conflink[2]
    thisconfbibdicts = []
    bibfile = conflink[0] + ".bib"
    #bibfile = bibfile.replace(" ", "_")
    bibfile = os.path.join(conflink_dir, bibfile)
    printlog("Scraping conference page %s , and creating bibtex entries in '%s' ..."%(conflink_url, bibfile))
    thisconfbibsdb = BibDatabase()
    thisconfbibsdb.entries = []
    ##############################################################################
    if conflink_year == "2014":
      printlog("Handling special site for year %s"%(conflink_year))
      confpage = requests.get(conflink_url)
      confpagetree = LH.fromstring(confpage.content)
      split_url = urlsplit(conflink_url)
      # urlunsplit takes and joins a five item iterable, we "" the last X items to remove the query string and fragment.
      this_base_url = urlunsplit((split_url.scheme, split_url.netloc, "", "", ""))
      confpagetree.make_links_absolute(base_url=this_base_url)
      confstring = confpagetree.xpath("//article[@class='item-page']/blockquote/h2/a")[0].text_content()
      confstringparts = confstring.split(",")
      confeds = confstringparts[0].replace("(Eds.)", "").strip()
      conftitle = confstringparts[1]
      #   Biblio's "Date Published" vs. Bibtex "month" (for conferences etc.)? [#855306] | Drupal.org https://www.drupal.org/node/855306
      # The standard bibtex types don't make a difference between the conference date and the publication date
      # For conference publications (inproceedings), is it customary to enter the conference dates into this field (e.g., month = {November 17--19},).
      confdate = confstringparts[2]
      # 'VENUE' or 'address';   Publisher, location, and year in @inproceedings and @incollection. https://github.com/moewew/biblatex-trad/issues/21
      # https://tex.stackexchange.com/questions/76566/how-to-show-the-location-of-a-conference-in-bibtex
      confplace = ", ".join( (confstringparts[3], confstringparts[4]) )
      confisbn = ""
      # here we have entries, generally as <p>, then inside:
      #  span, inside a with title and href, after it <b> for authors, and page number
      #  span with a with title and href, after it span with author and page numer
      # wget -qO- http://speech.di.uoa.gr/ICMC-SMC-2014/index.php | grep -ao '.........\.pdf' |wc says 282 papers incl. preface, same says $x("//a[contains(@href,'.pdf')]"), so 281 in all
      confpapers = confpagetree.xpath("//p[descendant::a[contains(@href,'.pdf')]]")
      icp = 0 ; icpdf = 0;
      re_pat_dots = re.compile("\.{3,}")
      for confpaper in confpapers: #[:10]:
        icp += 1
        confpapertitlecell = confpaper
        confpaperbibentry = {}
        # same for both types: the a child has the title and the url
        confpaperlink = confpapertitlecell.xpath(".//a")[0]
        confpaperbibentry['origtitle'] = confpaperlink.text_content()
        confpaperbibentry['title'] = titlecase(confpaperbibentry['origtitle'])
        confpaperbibentry['url'] = confpaperlink.attrib['href']
        #authstrcell = confpapertitlecell.xpath(".//b[descendant::span]")
        #authstr = ""
        ##for idx, ats in enumerate(authstrcell):
        ##  pprint.pprint("> %d/%d: '%s'"%(idx, len(authstr), etree.tostring(ats, pretty_print=True))) #ats.text_content().strip()))
        #if len(authstrcell)>=2:
        #  authstr = authstrcell[len(authstrcell)-1].text_content().strip()
        ## clean up commas:
        #if authstr:
        #  authstr = ",".join( filter(None, authstr.split(",")) )
        #else: # authstr still empty, try another derivation
        #  # select span that does not have children (Otherwise it has <a child, which is then the title with PDF link; also which does not have <a parent, and is not empty string
        #  ns = {"re": "http://exslt.org/regular-expressions"} # SO: 34047567
        #  authstrcell = confpapertitlecell.xpath(".//span[not(a) and not(ancestor::a) and not(re:match(., '^\s+$'))]", namespaces=ns)
        #  authstrcelltexts = [x.text_content() for x in authstrcell]
        #  #~ pprint.pprint(authstrcelltexts)
        #  # here can be different:
        #  # ['Aristotelis Hadjakos, Steffen Bock, and Fabien '
        #  #  'Levy............................................ 1840']
        #  # ['Kai Lassfolk and Mikko '
        #  #  'Ojanen........................................................................... '
        #  #  '1844']
        #  # ['DariuszJackowski, Francho Melendez, Andrzej Bauer,  PawelHendrich, '
        #  #  'CezaryDuchnowski........................................................................... '
        #  #  '88']
        #  # so simply join these first, then split at more than three dots with regex, and will get names and page number
        #  authstrcelltextsparts = re_pat_dots.split( "".join(authstrcelltexts) )
        #  authstrcelltextsparts = [x.strip() for x in authstrcelltextsparts]
        #  pprint.pprint(authstrcelltextsparts)
        #  authstr = authstrcelltextsparts[0]
        #  pagestr = authstrcelltextsparts[1]
        # bit easier - first, get all text which is not the paper title (in the a)
        # then, if it matches .... - split and obtain page number
        ns = {"re": "http://exslt.org/regular-expressions"} # SO: 34047567
        confpaperinfos = confpapertitlecell.xpath("*[not(self::a) and not(ancestor::a[@href]) and not(descendant::a[@href]) and not(re:match(., '^\s+$'))]", namespaces=ns)
        #~ print("Count: %d"%(len(confpaperinfos)))
        infopartsh = [etree.tostring(x, pretty_print=True) for x in confpaperinfos]
        #~ pprint.pprint(infopartsh)
        infoparts = [x.text_content() for x in confpaperinfos]
        # here, can either have 2 matches (for the bold names), or 1
        # when 2, name is in the first match, second match is the affiliation and dots and pagenumber
        # when 1, it is names and dots and pagenumber (no affiliation)
        # and once there is 3 elems, but they are names and dots and pagenumber (so as if 1)
        if len(confpaperinfos)==2:
          authstr = infoparts[0].strip()
          pagestr = re_pat_dots.split( infoparts[1] )[1].strip()
        else:
          #~ pprint.pprint(etree.tostring(confpapertitlecell, pretty_print=True))
          fullstr = "".join(infoparts) # to also handle the len 3 case
          #~ pprint.pprint("AAA" + fullstr)
          fullstrparts = re_pat_dots.split( fullstr )
          # if len is 1, then no dots have been found, then select the parent and repeat query there? No, it selects all
          # select only the next sibling
          if len(fullstrparts)!=2:
            foundDots = False
            cpsib = confpapertitlecell
            while not(foundDots):
              cpsib = cpsib.getnext()
              confpaperinfos.extend(cpsib.xpath("*[not(self::a) and not(ancestor::a[@href]) and not(descendant::a[@href]) and not(re:match(., '^\s+$'))]", namespaces=ns))
              infoparts = [x.text_content() for x in confpaperinfos]
              if re_pat_dots.findall( "".join(infoparts)): # findall, not match here
                foundDots = True
            fullstr = "".join(infoparts)
            fullstrparts = re_pat_dots.split( fullstr )
          authstr = fullstrparts[0].strip()
          pagestr = fullstrparts[1].strip()
        # filter extra commas in author string (last comma in single names messes up)
        authstr = ",".join(filter(None, authstr.split(","))).strip()
        confpaperbibentry['author'] = authstr.replace(",", " and")
        confpaperbibentry['pages'] = "%s-"%(pagestr)
        confpaperbibentry['numpaperorder'] = "%03d"%(icp)
        confpaperbibentry['origtype'] = "Conference paper"
        confpaperbibentry['ENTRYTYPE'] = "inproceedings" # this is it
        confpaperbibentry['ID'] = "smc:%s:%s"%(conflink_year, confpaperbibentry['numpaperorder']) # make a numeric id
        confpaperbibentry['booktitle'] = conftitle
        confpaperbibentry['issn'] = confissn
        confpaperbibentry['isbn'] = confisbn
        confpaperbibentry['year'] = conflink_year
        confpaperbibentry['month'] = confdate
        confpaperbibentry['editor'] = confeds
        confpaperbibentry['venue'] = confplace
        confpaperbibentry['publisher'] = ""
        confpaperbibentry['urlhome'] = ""
        confpaperbibentry['urlpdf'] = confpaperbibentry['url']
        if (".pdf" in confpaperbibentry['urlpdf']):
          icpdf += 1
          confpaperbibentry['file'] = "smc_%s_%s.pdf"%(conflink_year, confpaperbibentry['numpaperorder']) # for JabRef, and local PDF names
        else: confpaperbibentry['file'] = ""
        # only this one has volume!
        if "VOL_2" in confpaperbibentry['urlpdf']:
          confpaperbibentry['volume'] = "2"
        else:
          confpaperbibentry['volume'] = "1"
        thisconfbibdicts.append(confpaperbibentry)
        thisconfbibsdb.entries.append(confpaperbibentry)
        pprint.pprint(confpaperbibentry)
    ##############################################################################
    elif conflink_year == "2007":
      printlog("Handling special site for year %s"%(conflink_year))
      confpage = requests.get(conflink_url)
      confpagetree = LH.fromstring(confpage.content)
      split_url = urlsplit(conflink_url)
      # urlunsplit takes and joins a five item iterable, we "" the last X items to remove the query string and fragment.
      this_base_url = urlunsplit((split_url.scheme, split_url.netloc, "", "", ""))
      confpagetree.make_links_absolute(base_url=this_base_url)
      confstring = confpagetree.xpath("//div[@id='content']/div[@class='story']/h3/a")[0].text_content()
      confstringpartsA = confstring.split(":")
      confeds = confstringpartsA[0].replace("(Eds)", "").replace(",", " and").strip()
      confstringpartsB = [x.strip() for x in confstringpartsA[1].split(",")]
      conftitle = confstringpartsB[0].replace('"', '')
      conftitle = re.sub('\s+',' ',conftitle) # remove \n, \t in string
      confdate = confstringpartsB[1]
      confplace = ", ".join( (confstringpartsB[2], confstringpartsB[3]) )
      confisbn = confstringpartsB[4].replace("ISBN","").strip()
      #print(locals())
      # here we have h4/h5 as sections, followed by ul's with li's with a's with title and author and link to PDF
      # simply obtain the ul/a's, the sections don't matter here anyway
      confpapers = confpagetree.xpath("//div[@id='content']/div[@class='story']/ul/li/a")
      icp = 0 ; icpdf = 0;
      for confpaper in confpapers: #[:10]:
        icp += 1
        confpapertitlecell = confpaper
        confpaperbibentry = {}
        # here, the title cell has the paper title, then comma, then comma-separated list of authors
        # just split at each comma, take the first entry as title, and the rest as authors
        confpapertitlecellentries = [x.strip() for x in confpapertitlecell.text_content().split(',')]
        confpaperbibentry['origtitle'] = confpapertitlecellentries[0]
        confpaperbibentry['title'] = titlecase(confpaperbibentry['origtitle'])
        confpaperbibentry['url'] = confpapertitlecell.attrib['href']
        confpaperbibentry['numpaperorder'] = "%03d"%(icp)
        confpaperbibentry['origtype'] = "Conference paper"
        confpaperbibentry['ENTRYTYPE'] = "inproceedings" # this is it
        confpaperbibentry['ID'] = "smc:%s:%s"%(conflink_year, confpaperbibentry['numpaperorder']) # make a numeric id
        confpaperbibentry['author'] = " and ".join( confpapertitlecellentries[1:] )
        confpaperbibentry['pages'] = ""
        confpaperbibentry['booktitle'] = conftitle
        confpaperbibentry['issn'] = confissn
        confpaperbibentry['isbn'] = confisbn
        confpaperbibentry['year'] = conflink_year
        confpaperbibentry['month'] = confdate
        confpaperbibentry['editor'] = confeds
        confpaperbibentry['venue'] = confplace
        confpaperbibentry['publisher'] = ""
        confpaperbibentry['urlhome'] = ""
        confpaperbibentry['urlpdf'] = confpaperbibentry['url']
        if (".pdf" in confpaperbibentry['urlpdf']):
          icpdf += 1
          confpaperbibentry['file'] = "smc_%s_%s.pdf"%(conflink_year, confpaperbibentry['numpaperorder']) # for JabRef, and local PDF names
        else: confpaperbibentry['file'] = ""
        thisconfbibdicts.append(confpaperbibentry)
        thisconfbibsdb.entries.append(confpaperbibentry)
        pprint.pprint(confpaperbibentry)
    ##############################################################################
    else:
      confpage = requests.get(conflink_url)
      confpagetree = LH.fromstring(confpage.content)
      confpagetree.make_links_absolute(base_url=url_base_smc)
      # .view-content > .views-table > tbody:nth-child(2)
      confpapers = confpagetree.xpath("//div[@class='view-content']/table[contains(@class, 'views-table')]/tbody/tr")
      icp = 0 ; icpdf = 0;
      re_pat_pagenums = re.compile(r"p\.(\d+-\d+)")
      for confpaper in confpapers: #[:10]:
        icp += 1
        # first td in tr is title, it has <a> inside which contains title and URL
        #pprint.pprint("%02d "%(icp) + confpaper[0][0].text_content()) #ok
        confpapertitlecell = confpaper.xpath("td[1]/a")[0]
        confpaperbibentry = {}
        confpaperbibentry['origtitle'] = confpapertitlecell.text_content()
        confpaperbibentry['title'] = titlecase(confpaperbibentry['origtitle'].lower())
        confpaperbibentry['url'] = confpapertitlecell.attrib['href']
        confpaperbibentry['numpaperorder'] = "%03d"%(icp)
        # second td is multiple <a> links with authors, but with short names
        # better to scrape each paper's HTML page, it has authors full names
        confpaperpage = requests.get(confpaperbibentry['url'])
        confpaperpagetree = LH.fromstring(confpaperpage.content)
        confpaperpagetree.make_links_absolute(base_url=url_base_smc)
        # this now is "type" "Conference paper" (so @inproceedings+booktitle?)
        # must use last() here to skip the <h>reading in this node? Not really, is same without, here
        confpaperbibentry['origtype'] = confpaperpagetree.xpath("//div[@class='biblio_type']/text()[last()]")[0].strip()
        #confpaperbibentry['type'] = "inproceedings" # no dice
        confpaperbibentry['ENTRYTYPE'] = "inproceedings" # this is it
        confpaperbibentry['ID'] = "smc:%s:%s"%(conflink_year, confpaperbibentry['numpaperorder']) # make a numeric id
        # here select only the <a> child nodes - each of them has the full author name
        confpaperauthors = confpaperpagetree.xpath("//div[@class='biblio_authors']/a")
        # extract only the names via generator expression
        confpaperauthors = [ cpauthor.text_content() for cpauthor in confpaperauthors ]
        # concatenate names with "and", as per bibtex
        confpaperbibentry['author'] = " and ".join(confpaperauthors)
        # this now is: "Proceedings of the Sound and Music Computing Conference 2016, SMC 2016, Hamburg, Germany (2016)"
        # actually, the format is widely different, and sometimes even plain wrong
        # so booktitle will have to be manually edited
        # however, for 2013 and 2012, there are also page numbers embedded here as p.05-10...
        # however, one of those uses en-dash instead of minus, so handle that too
        confpaperbibentry['booktitle'] = confpaperpagetree.xpath("//div[@class='biblio_source']/text()[last()]")[0].strip()
        confpaperbibentry['booktitle'] = confpaperbibentry['booktitle'].replace("–", "-")
        respn = re_pat_pagenums.findall(confpaperbibentry['booktitle'])
        if respn:
          confpaperbibentry['pages'] = respn[0]
          # also delete from string
          confpaperbibentry['booktitle'] = re_pat_pagenums.sub("", confpaperbibentry['booktitle'])
        else: confpaperbibentry['pages'] = ""
        confpaperbibentry['issn'] = confissn
        # now the ISBN - a bit tricky
        confpaperbibentry['isbn'] = confpaperpagetree.xpath("//h3[text()='ISBN:']/following-sibling::text()[1]")
        if confpaperbibentry['isbn']: # only handle if it is present:
          confpaperbibentry['isbn'] = confpaperbibentry['isbn'][0].strip()
        else:
          confpaperbibentry['isbn'] = ""
        confpaperbibentry['year'] = conflink_year
        confpaperbibentry['month'] = ""
        confpaperbibentry['editor'] = ""
        confpaperbibentry['venue'] = ""
        confpaperbibentry['publisher'] = ""
        # this is the URL on the author home page, which is given on the paper page confpaperbibentry['url']:
        confpaperbibentry['urlhome'] = confpaperpagetree.xpath("//h3[text()='URL:']/following::a[1]") #[0].attrib['href']
        if confpaperbibentry['urlhome']: # only handle if it is present:
          confpaperbibentry['urlhome'] = confpaperbibentry['urlhome'][0].attrib['href']
        else:
          confpaperbibentry['urlhome'] = ""
        confpaperbibentry['urlpdf'] = confpaperpagetree.xpath("//table[@id='attachments']/tbody/tr/td[1]/a")
        if confpaperbibentry['urlpdf']: # only handle if it is present:
          confpaperbibentry['urlpdf'] = confpaperbibentry['urlpdf'][0].attrib['href']
        else:
          confpaperbibentry['urlpdf'] = ""
        # for older proceedings, urlpdf is "" and urlhome is actually the pdf link; check for this and replace:
        if ( (confpaperbibentry['urlpdf'] == "") and (".pdf" in confpaperbibentry['urlhome']) ):
          confpaperbibentry['urlpdf'] = confpaperbibentry['urlhome']
          confpaperbibentry['urlhome'] = ""
        if (".pdf" in confpaperbibentry['urlpdf']):
          icpdf += 1
          confpaperbibentry['file'] = "smc_%s_%s.pdf"%(conflink_year, confpaperbibentry['numpaperorder']) # for JabRef, and local PDF names
        else: confpaperbibentry['file'] = ""
        thisconfbibdicts.append(confpaperbibentry)
        thisconfbibsdb.entries.append(confpaperbibentry)
        pprint.pprint(confpaperbibentry)
    # found papers, and found PDFs
    conflink.append(icp)
    conflink.append(icpdf)
    conflinks[ conflink[3] ] = conflink # save/update the modified conflink!
    # save bib file
    with open(bibfile, 'w') as thebibfile:
      #thebibfile.write(bibwriter.write(thisconfbibsdb)) # may cause UnicodeEncodeError: 'ascii' codec can't encode character u'\xf2' in position 4314: ordinal not in range(128)
      # see https://github.com/sciunto-org/python-bibtexparser/issues/51
      bibtex_str = bibtexparser.dumps(thisconfbibsdb)
      if sys.version_info[0]<3: # python 2
        thebibfile.write(bibtex_str.encode('utf8'))
      else: #python 3
        thebibfile.write(bibtex_str)
    allconfsbibdicts.append(thisconfbibdicts)
    allconfsbibdbs.append(thisconfbibsdb)

  printlog("Report: Conference year - found papers/found PDFs:")
  foundptotal = 0; foundpdftotal = 0;
  for conflink in conflinks:
    if len(conflink)==4: #short
      fp, fpdf = "0", "0"
    else:
      fp, fpdf = conflink[4], conflink[5]
    printlog( "> %s - %s/%s"%(conflink[2], fp, fpdf) )
    foundptotal += int(fp)
    foundpdftotal += int(fpdf)
  printlog("Total: %s/%s"%(foundptotal,foundpdftotal))

  ts_bibpartend = datetime.now()
  printlog("Script bib part start: %s ; end: %s ; duration: %s"%(ts_bibpartstart.strftime("%Y-%m-%d %H:%M:%S"), ts_bibpartend.strftime("%Y-%m-%d %H:%M:%S"), str(ts_bibpartend-ts_bibpartstart)))


printlog("Download online PDFs? [y/n]")
choice = input().lower()
doPdfFiles = False
if choice == "y":
  doPdfFiles = True

# read the .bib files here, so this part can run independent
# else have to wait for 7 mins for the allconfsbibdicts to be reconstructed...
if doPdfFiles:
  ts_pdfpartstart = datetime.now()
  for cidx, conflink in enumerate(conflinks):
    conflink_dir = os.path.join(dir_data, conflink[0])
    #thisconfbibdicts = allconfsbibdicts[cidx]
    #for confpaperbibentry in thisconfbibdicts:
    bibfile = conflink[0] + ".bib"
    bibfile = os.path.join(conflink_dir, bibfile)
    printlog("\n"+bibfile)
    with open(bibfile) as bibtex_file:
      bibtex_str = bibtex_file.read()
    bib_database = bibtexparser.loads(bibtex_str)
    for confpaperbibentry in bib_database.entries:
      if (".pdf" in confpaperbibentry['urlpdf']):
        printlog("%s : %s"%(confpaperbibentry['file'], confpaperbibentry['urlpdf']))
        localfpath = os.path.join(conflink_dir, confpaperbibentry['file'])
        dl = 0
        with open(localfpath, "wb") as f:
          #print "Downloading %s" % file_name
          response = requests.get(confpaperbibentry['urlpdf'], stream=True)
          total_length = response.headers.get('content-length')
          if total_length is None: # no content length header
            #f.write(response.content)
            for data in response.iter_content(chunk_size=32768):#4096):
              dl += len(data)
              f.write(data)
              sys.stdout.write(".")
              sys.stdout.flush()
          else:
            total_length = int(total_length)
            for data in response.iter_content(chunk_size=32768):#4096):
              dl += len(data)
              f.write(data)
              done = int(50 * dl / total_length)
              #sys.stdout.write("\r[%s%s]" % ('=' * done, ' ' * (50-done)) )
              sys.stdout.write("=")
              sys.stdout.flush()
      printlog(" got %d bytes."%(dl))
  ts_pdfpartend = datetime.now()
  printlog("Script pdf part start: %s ; end: %s ; duration: %s"%(ts_pdfpartstart.strftime("%Y-%m-%d %H:%M:%S"), ts_pdfpartend.strftime("%Y-%m-%d %H:%M:%S"), str(ts_pdfpartend-ts_pdfpartstart)))

printlog("Done getting .bib info for all conferences. Check and edit the .bibs manually")
logfile.close()
