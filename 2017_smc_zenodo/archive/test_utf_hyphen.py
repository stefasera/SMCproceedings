#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, sys
import re
from pprint import pprint

aa = "Proceedings of the Sound and Music Computing Conference 2013, SMC 2013, Logos Verlag Berlin, Stockholm, Sweden, p.103–108 (2013)"
re_pat_pagenums = re.compile(r"p\.(\d+-\d+)")
bb = aa.replace("–", "-")
pprint(aa)
pprint(bb)
pprint(re_pat_pagenums.findall(bb))