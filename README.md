# moon-netstring

纯 MoonBit netstrings 编解码库，可与 Python 的 pynetstring 0.5 和 Twisted 25.5.0 交换标准 netstrings。支持 wasm、wasm-gc、JavaScript 和 native，核心只依赖 MoonBit 标准库。

## 功能

- **编码**：支持单条、批量及 Buffer 追加编码。`encoded_length` 精确计算帧长，`encode_header` 生成分段发送所需的长度头。
- **解码**：一次读取全部消息，或用 `decode_prefix` 读取首帧并返回已消费字节数。`try_decode_prefix` 可识别尚未收齐的帧。
- **增量 `Decoder`**：按完整帧交付，限制单帧长度，支持暂停、续喂、EOF 检查和复位。
- **流式 `StreamingDecoder`**：以 `Begin/Data/End` 分段交付，无须缓存整帧；错误包含类别和绝对字节偏移。
- **SCGI 请求编解码**：`scgi` 子包复用 netstring 分帧，校验 SCGI 字段，并按 `CONTENT_LENGTH` 交付二进制正文。[SCGI 使用指南](docs/SCGI.md)

长度按字节计算。例如 `3:a,b,` 的载荷为 `a,b`，空载荷编码为 `0:,`。解码时检查多余前导零、超长声明、缺失逗号及截断输入。

## 安装与使用

```bash
moon add tc-adventureking/netstring@0.1.2
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

[完整 API](pkg.generated.mbti) · [Python 对照与差异](docs/COMPATIBILITY.md) · [使用场景](docs/USAGE.md) · [Mooncakes](https://mooncakes.io/docs/tc-adventureking/netstring/)

## 示例与测试

安装 MoonBit 工具链后在仓库运行：

```bash
moon run examples/main
moon run examples/transactional
moon run examples/prefix_record
moon run examples/scgi_request
```

第一个示例分两次喂入 `5:hello,0:,`，依次收到 `hello` 和空消息。第二个示例提交第一帧的 5 字节，第二帧在偏移 13 处出错，只撤销该帧暂存的 3 字节。第三个示例读取占 21 字节的元数据帧，余下 8 字节作为原始正文保留。

本地使用 moon 0.1.20261104、moonc v0.10.20 在四个后端各运行 24 项契约测试和前三个示例。与 pynetstring、Twisted 的对照覆盖 7,054 组基础输入流，另用独立解析器核对了短输入在不同拆分位置、长度上限和暂停方式下的帧序列与错误偏移。

SCGI 示例逐字节喂入一个包含 NUL 和非 UTF-8 字节的 POST 请求，检查正文能否原样还原。可用 `moon test scgi` 运行仓库内的 SCGI 回归测试。

## 许可

项目代码使用 [MIT](LICENSE)。协议依据 [D. J. Bernstein 的 netstrings 规范](https://cr.yp.to/proto/netstrings.txt)，行为参考 [pynetstring 0.5](https://github.com/rj79/pynetstring) 和 [Twisted 25.5.0](https://github.com/twisted/twisted/blob/twisted-25.5.0/src/twisted/protocols/basic.py)。
