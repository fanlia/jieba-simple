
# rewrite from https://github.com/fxsjy/jieba

from pathlib import Path
from math import log
import re

re_eng = re.compile('[a-zA-Z0-9]', re.U)
DEFAULT_DICTIONARY = Path(__file__).parent / 'dict.txt'

class Tokenizer(object):
    def __init__(self, dictionary=DEFAULT_DICTIONARY):
        self.dictionary = dictionary
        self.freq = {}
        self.total = 0
        self.initialized = False

    def initialize(self):
        self.freq, self.total = self.gen_pfdict(self.dictionary)
        self.initialized = True

    def check_initialized(self):
        if not self.initialized:
            self.initialize()

    def gen_pfdict(self, dictionary):
        lfreq = {}
        ltotal = 0
        with open(dictionary) as f:
            for lineno, line in enumerate(f, start=1):
                try:
                    line = line.strip()
                    word, freq = line.split(' ')[:2]
                    freq = int(freq)
                    lfreq[word] = freq
                    ltotal += freq

                    for ch in range(len(word)):
                        wfrag = word[:ch+1]
                        if wfrag not in lfreq:
                            lfreq[wfrag] = 0
                except ValueError:
                    raise ValueError('invalid dictionary entry in {} at Line {}: {}'.format(dictionary, lineno, line))
        return lfreq, ltotal

    def calc(self, sentence, DAG):
        N = len(sentence)
        route = {}
        route[N] = (0, 0)
        logtotal = log(self.total)
        for idx in range(N-1, -1, -1):
            ps = []
            for x in DAG[idx]:
                word = sentence[idx:x+1]
                freq = self.freq.get(word, 1)
                logword = log(freq)
                p = (logword - logtotal + route[x+1][0], x)
                ps.append(p)
            route[idx] = max(ps)
        return route

    def get_DAG(self, sentence):
        self.check_initialized()
        DAG = {}
        N = len(sentence)
        for k in range(N):
            tmplist = []
            i = k
            frag = sentence[k]
            while i < N and frag in self.freq:
                if self.freq[frag]:
                    tmplist.append(i)
                i += 1
                frag = sentence[k:i+1]
            if not tmplist:
                tmplist.append(k)
            DAG[k] = tmplist
        return DAG

    def cut(self, sentence):
        DAG = self.get_DAG(sentence)
        route = self.calc(sentence, DAG)

        x = 0
        N = len(sentence)
        buf = ''
        while x < N:
            y = route[x][1] + 1
            word = sentence[x:y]
            if re_eng.match(word) and len(word) == 1:
                buf += word
            else:
                if buf:
                    yield buf
                    buf = ''
                yield word
            x = y
        if buf:
            yield buf
            buf = ''

dt = Tokenizer()

cut = dt.cut
