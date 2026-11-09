# moon-netstring

纯 MoonBit netstrings 编解码库，将任意二进制消息表示为“字节长度:内容,”。支持 wasm、wasm-gc、JavaScript 和 native；核心只依赖 MoonBit 标准库。

## 功能

- **编码**：单条、批量及 Buffer 追加编码，精确计算线格式大小，生成分段发送所需的长度头。
- **解码**：严格格式校验，支持完整输入、首帧前缀读取和未完成前缀探测。
- **增量 `Decoder`**：按完整帧交付，限制单帧长度，支持暂停、续喂、EOF 检查和复位。
- **流式 `StreamingDecoder`**：以 `Begin/Data/End` 分段交付，无须缓存整帧；错误包含类别和绝对字节偏移。

长度按字节计算，空载荷为 `0:,`；拒绝多余前导零、超长声明、缺失逗号及截断输入。

## 安装与使用

```bash
moon add tc-adventureking/netstring@0.1.1
```

在 `moon.pkg` 中导入：

```moonbit
import { "tc-adventureking/netstring" @netstring, }
```

```moonbit
fn main raise {
  let wire = @netstring.encode_all([b"hello"[:], b""[:]])
  let decoder = @netstring.Decoder::new(max_len=1024)
  decoder.feed(wire[:4], fn(frame) { println(frame.to_owned()) })
  decoder.feed(wire[4:], fn(frame) { println(frame.to_owned()) })
  decoder.finish()
}
```

增量接口默认每帧最多 99,999 字节。`max_len` 只限制单帧；流式片段在 `End` 后才算完整消息。长期保留大块中的小视图时，可按需 `to_owned()`。

[完整 API](https://mooncakes.io/docs/tc-adventureking/netstring/) · [使用指南](https://github.com/tc-adventureking/moon-netstring/blob/main/docs/USAGE.md) · [源码](https://github.com/tc-adventureking/moon-netstring)

## 示例

安装 MoonBit 工具链后在仓库运行：

```bash
moon run examples/main
moon run examples/transactional
moon run examples/prefix_record
```

三个示例分别展示基本编解码、流式提交与撤销，以及元数据帧后保留原始二进制正文。

## 许可与参考

代码使用 [MIT](https://github.com/tc-adventureking/moon-netstring/blob/main/LICENSE)。格式依据 [D. J. Bernstein netstrings](https://cr.yp.to/proto/netstrings.txt)，行为参考 [pynetstring 0.5](https://github.com/rj79/pynetstring) 和 [Twisted 25.5.0](https://github.com/twisted/twisted/blob/twisted-25.5.0/src/twisted/protocols/basic.py)（均为 MIT）；实现为 MoonBit 原生代码，未复制参考项目源码。
