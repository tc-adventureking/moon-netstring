# netstring

纯 MoonBit netstrings 编解码库。将任意二进制消息编码成 `字节长度:内容,`，并从任意切块的字节流中恢复消息边界。适合进程通信、记录文件和已有 netstrings 协议的接入。零第三方依赖，提供完整消息与分段输出两种接收方式。

## 功能

- 单条、批量编码和向已有 Buffer 追加编码。
- 严格解码，拒绝前导零、无效长度、缺逗号和截断输入。
- 有界增量 Decoder：完整消息通过逗号校验后交付。
- StreamingDecoder：按输入片段交付，不缓存整条消息。
- 每个错误包含稳定类别和绝对字节偏移；失败锁定、EOF 检查及显式复位。

## 安装与使用

当前为本地源码交付，尚未发布 Mooncakes。将源码目录命名为 `netstring`，与消费项目 `app` 放在同一目录，运行：

```sh
moon work init netstring app
```

在 `app/moon.mod` 添加模块依赖：

```toml
import { "tc-adventureking/netstring@0.1.0", }
```

在 `app/moon.pkg` 引入：

```moonbit
import { "tc-adventureking/netstring" @netstring, }
```

需要 2026-11-04 或更新的 MoonBit 工具链。核心使用标准库，可编译到 wasm、wasm-gc、js 和 native。可运行示例位于 `examples/main`：

```sh
moon run examples/main
```

## 使用示例

```moonbit
let wire = @netstring.encode_all([b"hello"[:], b""[:]])
// b"5:hello,0:,"
let frames = @netstring.decode(wire)
// [b"hello"[:], b""[:]]

let decoder = @netstring.Decoder::new(max_len=1024)
decoder.feed(b"5:he", fn(frame) { println(frame.to_owned()) })
decoder.feed(b"llo,0:,", fn(frame) { println(frame.to_owned()) })
decoder.finish()
```

大消息可以分段消费：

```moonbit
let stream = @netstring.StreamingDecoder::new(max_len=10_000_000)
stream.feed(b"5:hello,", fn(event) {
  match event {
    Begin(length) => println("开始接收 \{length} 字节")
    Data(bytes) => println(bytes.to_owned())
    End => println("消息已完整接收")
  }
})
stream.finish()
```

调用这些 API 的函数须声明 `raise` 或捕获 `NetstringError`。

## 行为边界

长度按字节计算。空载荷为 `0:,`；空输入解码为零条消息。仅允许 ASCII 十进制数字，只有 `0` 可以以零开头，不跳过空白。负载可含逗号、冒号、零字节及任意非 UTF-8 字节。

增量解码默认每帧最多 99,999 字节；`max_len=0` 仅接受空帧，负值返回 `InvalidLimit`。一次性 `decode` 默认上限为 2,147,483,647，也可显式设置更小上限。逐位检查长度，超限立即拒绝，不按声明长度预分配内存。

`Decoder` 仅交付通过终止逗号校验的完整消息。`StreamingDecoder` 的 `Data` 是尚未提交的片段，只有 `End` 表示该帧成功；出错或 EOF 截断时，调用方须撤销当前帧的处理。空帧只有 `Begin(0)`、`End`，没有空 `Data`。不同切块方式可能产生不同的 `Data` 分段，合并后的载荷及帧边界一致。

错误偏移从构造或 `reset()` 起算，从 0 开始。格式错误指向出错字节，`Truncated` 指向 EOF。失败后保留首个错误，后续 `feed`、`finish` 重抛该错误；`reset` 开始新流。成功 `finish` 关闭当前流，重复调用幂等，之后 `feed` 返回 `Closed`。同一块里错误之前的完整帧会先回调交付。本格式不能可靠重同步，发生格式错误后应由调用方关闭连接或明确开始新流。

回调可以保留 BytesView；它会保留底层 Bytes。单块内的消息及流式片段不复制；跨块完整消息按需缓冲，缓冲的载荷字节不超过 `max_len`。运行时容量、输入块、回调保存的输出及 BytesView 保留的底层 Bytes 不计入该上限。StreamingDecoder 自身不保存载荷，只保存解析状态。回调中对同一解码器调用 `feed`、`finish`、`reset` 会返回 `Reentrant`，不修改当前状态。

本库处理字节，不自动编码文本，不执行网络或文件 I/O，也不提供校验和、加密及身份认证。

## 许可与参考

MIT。参考 [Daniel J. Bernstein 的 netstrings 格式](https://cr.yp.to/proto/netstrings.txt)，以 [pynetstring 0.5](https://github.com/rj79/pynetstring)（MIT）对标功能，以 [Twisted 25.5.0 NetstringReceiver](https://docs.twisted.org/en/twisted-25.5.0/api/twisted.protocols.basic.NetstringReceiver.html)（MIT）交叉核对严格格式。实现为 MoonBit 原生代码，未复制参考项目源码。

与 pynetstring 的明确差异：本库按格式要求拒绝多余前导零；增量接口默认有限，且 0 不代表无限；流式接口用 `Begin/Data/End` 事件而非空字节结束标记；批量编码返回拼接后的 Bytes，而非 Python 列表；提供 EOF、复位与锁定错误语义。只对标字节协议与编解码能力，不对标 Python 类型转换或 Twisted 网络运行时。
