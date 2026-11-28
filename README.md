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

需要 `moonc 1.0.0-rc1` 或更高版本。CI 固定使用 `1.0.0-rc1+3c0520448` 的编译器和标准库。安装后运行 `moon version --all`，在 `moonc` 一行核对版本。[MoonBit 安装指南](https://www.moonbitlang.com/download/)

首次试用可以创建一个示例项目，并在项目根目录添加依赖。

```bash
moon new --user example netstring-demo
cd netstring-demo
moon add tc-adventureking/netstring@0.2.1
```

将 `cmd/main/moon.pkg` 的内容替换为以下配置。

```moonbit
import { "tc-adventureking/netstring" @netstring, }
pkgtype(kind: "executable")
```

将 `cmd/main/main.mbt` 的内容替换为以下程序。第一次喂入 `5:he`，第二次补齐 `hello` 并带上一个空帧。

```moonbit
fn main raise {
  let wire = @netstring.encode_all([b"hello"[:], b""[:]])
  let decoder = @netstring.Decoder::new(max_len=1024)
  decoder.feed(wire[:4], fn(frame) { println(frame.to_owned()) })
  decoder.feed(wire[4:], fn(frame) { println(frame.to_owned()) })
  decoder.finish()
}
```

在示例项目根目录运行 `moon run cmd/main`，预期输出如下。

```text
b"hello"
b""
```

增量接口默认每帧最多 99,999 字节。`max_len` 只限制单帧；流式片段在 `End` 后才算完整消息。长期保留大块中的小视图时，可按需 `to_owned()`。

[完整 API](pkg.generated.mbti) · [Python 对照与差异](docs/COMPATIBILITY.md) · [使用场景](docs/USAGE.md) · [Mooncakes](https://mooncakes.io/docs/tc-adventureking/netstring/)

## 示例与测试

在仓库根目录运行以下命令。CI 对 `js`、`wasm`、`wasm-gc`、`native` 分别执行检查、构建、测试和四个示例，本地可替换 `--target` 的值。

```bash
moon check --target js --deny-warn
moon build --target js --deny-warn
moon test --target js --deny-warn
moon run examples/main --target js
moon run examples/transactional --target js
moon run examples/prefix_record --target js
moon run examples/scgi_request --target js
```

| 示例 | 输入与处理 | 可核对的结果 |
|---|---|---|
| `main` 消息流 | 将 `5:hello,0:,` 分两次喂入，依次交付完整帧 | 收到 `b"hello"` 和 `b""` 两条消息 |
| `transactional` 分块写入 | 先暂存流式片段，读到结束事件才提交。第二帧的终止字节有误 | 已提交 1 帧、5 字节，在偏移 13 撤销 3 字节，待提交量归零 |
| `prefix_record` 混合格式记录 | 读取首帧元数据，再按消费长度切出原始正文 | `header_wire_bytes=21`，余下 8 字节含 NUL、逗号和 `0xff` |
| `scgi_request` Web 网关 | 编码发往 `/upload` 的 POST 请求，逐字节送入 SCGI 解码器 | 打印 `content_length=8` 和 `request_complete`，断言还原的正文与输入逐字节相同 |

根包测试覆盖整批编解码、跨块、暂停续喂、非法帧和 EOF。SCGI 子包另含规范样例、Nginx 报文和截断测试。[持续集成](https://github.com/tc-adventureking/moon-netstring/actions/workflows/ci.yml) · [SCGI 测试与用法](docs/SCGI.md)

在 Git 检出中运行 `python3 scripts/count_library.py v0.2.0` 可逐文件复核实现行数。仅计根包和 `scgi/` 的手写库实现 `.mbt`，排除测试、示例、生成接口、空行和纯行注释，合计 739 行。再排除不含字母、数字或下划线的行，合计 585 行。

## 许可

项目代码使用 [MIT](LICENSE)。pynetstring 0.5 和 Twisted 25.5.0 均为 MIT，用于字节行为对照。SCGI 测试采用公有领域规范中的请求样例。各项来源、许可证及参考范围见[参考与归属](docs/COMPATIBILITY.md#参考与归属)。
