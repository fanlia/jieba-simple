
package jieba

import (
  "fmt"
  "reflect"
  "testing"
)

func TestCut(t *testing.T) {

  sentence := "我来到北京清华大学"
  result := []string{}
  for word := range Cut(sentence) {
    result = append(result, word)
  }
  fmt.Println(result)
  want := []string{"我", "来到", "北京", "清华大学"}

  if !reflect.DeepEqual(result, want) {
    t.Errorf("expect: %s got: %s", want, result)
  }
}
