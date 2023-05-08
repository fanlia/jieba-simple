
package jieba

import (
  "bufio"
  "log"
  "math"
  "os"
  "regexp"
  "sort"
  "strconv"
  "strings"
)

var re_eng = regexp.MustCompile("[a-zA-Z0-9]")
var DEFAULT_DICTIONARY = "dict.txt"

type Tokenizer struct {
  dictionary string
  freq map[string]int
  total int
  initialized bool
}

func (self *Tokenizer) initialize() {
  self.freq, self.total = self.gen_pfdict(self.dictionary)
  self.initialized = true
}

func (self *Tokenizer) check_initialized() {
  if !self.initialized {
    self.initialize()
  }
}

func (self *Tokenizer) gen_pfdict(dictionary string) (map[string]int, int) {
  lfreq := make(map[string]int)
  ltotal := 0

	file, err := os.Open(dictionary)

	if err != nil {
		log.Fatalf("Error when opening file: %s", err)
  }

	defer file.Close()

	fileScanner := bufio.NewScanner(file)

  lineno := 1
	for fileScanner.Scan() {
    line := strings.TrimSpace(fileScanner.Text())
    chunks := strings.Split(line, " ")[:2]
    word := chunks[0]
    freq, err := strconv.ParseInt(chunks[1], 0, 0) 
    if err != nil {
      log.Fatalf("invalid dictionary entry in %s at Line %d: %s", dictionary, lineno, line)
    }
    lfreq[word] = int(freq)
    ltotal += int(freq)

    chars := []rune(word)

    for ch:=0; ch<len(chars); ch++ {
      wfrag := string(chars[:ch+1])
      if _, ok := lfreq[wfrag]; !ok {
        lfreq[wfrag] = 0
      }
    }
	}

	if err := fileScanner.Err(); err != nil {
		log.Fatalf("Error while reading file: %s", err)
	}

  return lfreq, ltotal
}

type routevalue struct {
  x float64
  y int
}

func (self *Tokenizer) calc(sentence []rune, DAG map[int][]int) map[int]routevalue {
  N := len(sentence)
  route := make(map[int]routevalue)
  route[N] = routevalue{0.0, 0}
  logtotal := math.Log(float64(self.total))

  for idx:=N-1; idx>-1; idx-- {
    ps := []routevalue{}
    for _, x := range DAG[idx] {
      word := string(sentence[idx:x+1])
      freq, ok := self.freq[word]
      if !ok {
        freq = 1
      }
      logword := math.Log(float64(freq))
      p := routevalue{logword - logtotal + route[x+1].x, x}
      ps = append(ps, p)
    }
    sort.Slice(ps, func (i int, j int) bool {
      a := ps[i]
      b := ps[j]
      if a.x == b.x {
        return a.y > b.y
      } else {
        return a.x > b.x
      }
    })
    route[idx] = ps[0]
  }
  return route
}

func (self *Tokenizer) get_DAG(sentence []rune) map[int][]int {
  self.check_initialized()
  DAG := make(map[int][]int)
  N := len(sentence)

  for k:=0; k<N; k++ {
    tmplist := []int{}
    i := k
    for i < N {
      frag := string(sentence[k:i+1])
      freq, ok := self.freq[frag]
      if !ok {
        break
      }
      if freq > 0 {
        tmplist = append(tmplist, i)
      }
      i += 1
    }
    if len(tmplist) == 0 {
        tmplist = append(tmplist, k)
    }
    DAG[k] = tmplist
  }

  return DAG
}

func (self *Tokenizer) cut(sentence []rune) chan string  {
  DAG := self.get_DAG(sentence)
  route := self.calc(sentence, DAG)
  c := make(chan string)

  x := 0
  N := len(sentence)
  buf := []rune{}

  go func() {
    for x < N {
      y := route[x].y + 1
      word := sentence[x:y]
      if re_eng.Match([]byte(string(word))) && len(word) == 1 {
        buf = append(buf, word...)
      } else {
        if len(buf) > 0 {
          c <- string(buf)
          buf = []rune{}
        }
        c <- string(word)
      }
      x = y
    }
    if len(buf) > 0 {
      c <- string(buf)
      buf = []rune{}
    }
    close(c)
  }()

  return c
}

var dt = Tokenizer{
  dictionary: DEFAULT_DICTIONARY,
}

func Cut(sentence string) chan string {
  return dt.cut([]rune(sentence))
}

