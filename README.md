# jieba-simple
不同语言实现结巴分词算法(按字典)

## 如何使用

### nodejs

```js
import jieba from './jieba.js'

let result = []
for await (const word of jieb.cut('我来到北京清华大学')) {
    result.push(word)
}
console.log(result)
#=> ['我', '来到', '北京', '清华大学']
```

### python3

```py
import jieba
result = list(jieba.cut('我来到北京清华大学'))
print(result)
#=> ['我', '来到', '北京', '清华大学']
```

## 感谢

https://github.com/fxsjy/jieba
