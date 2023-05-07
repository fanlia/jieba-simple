
import { open } from 'node:fs/promises'

const re_eng = /[a-zA-Z0-9]/u
const DEFAULT_DICTIONARY = new URL('./dict.txt', import.meta.url)

export class Tokenizer {
  constructor(dictionary = DEFAULT_DICTIONARY) {
    this.dictionary = dictionary
    this.freq = {}
    this.total = 0
    this.initialized = false
  }

  async initialize() {
      const [ freq, total ] = await this.gen_pfdict(this.dictionary)
      this.freq = freq
      this.total = total
      this.initialized = true
  }

  async check_initialized() {
    if (!this.initialized) {
      await this.initialize()
    }
  }

  async gen_pfdict(dictionary) {
    let lfreq = {}
    let ltotal = 0

    let file

    try {
      file = await open(dictionary)
      let lineno = 1

      for await (let line of file.readLines()) {
        try {
          line = line.trim()
          let [word, freq] = line.split(' ', 2)
          freq = parseInt(freq)
          lfreq[word] = freq
          ltotal += freq

          for (let ch = 0; ch < word.length; ch++) {
            const wfrag = word.slice(0, ch+1)
            if (lfreq[wfrag] === undefined) {
              lfreq[wfrag] = 0
            }
          }
        } catch (e) {
          throw new Error(`invalid dictionary entry in ${dictionary} at Line ${lineno}: ${line}`)
        }
      }
    } finally {
      if (file) {
        await file.close()
      }
    }

    return [lfreq, ltotal]
  }

  calc(sentence, DAG) {
    const N = sentence.length
    let route = {}
    route[N] = [0, 0]
    const logtotal = Math.log(this.total)
    for (let idx = N-1; idx > -1; idx += -1) {
      let ps = []
      for (const x of DAG[idx]) {
        const word = sentence.slice(idx, x+1)
        const freq = this.freq[word] || 1
        const logword = Math.log(freq)
        const p = [logword - logtotal + route[x+1][0], x]
        ps.push(p)
      }
      route[idx] = ps.sort((a, b) => b[0] === a[0] ? b[1] - a[1] : b[0] - a[0])[0]
    }
    return route
  }

  async get_DAG(sentence) {
    await this.check_initialized()
    let DAG = {}
    const N = sentence.length
    for (let k = 0; k < N; k++) {
      let tmplist = []
      let i = k
      let frag = sentence[k]
      while (i < N && this.freq[frag] !== undefined) {
        if (this.freq[frag] > 0) {
          tmplist.push(i)
        }
        i += 1
        frag = sentence.slice(k, i+1)
      }
      if (tmplist.length === 0) {
        tmplist.push(k)
      }
      DAG[k] = tmplist
    }
    return DAG
  }

  async * cut(sentence) {
    const DAG = await this.get_DAG(sentence)
    const route = this.calc(sentence, DAG)

    let x = 0
    const N = sentence.length
    let buf = ''
    while (x < N) {
      const y = route[x][1] + 1
      const word = sentence.slice(x, y)
      if (re_eng.test(word) && word.length === 1) {
        buf += word
      } else {
        if (buf) {
          yield buf 
          buf = ''
        }
        yield word
      }
      x = y
    }
    if (buf) {
      yield buf
      buf = ''
    }
  }
}

export const dt = new Tokenizer()

export const cut = dt.cut.bind(dt)
