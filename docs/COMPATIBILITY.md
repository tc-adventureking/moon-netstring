# Python 对照与差异

本库依据 [D. J. Bernstein netstrings 格式](https://cr.yp.to/proto/netstrings.txt)，以 [pynetstring 0.5](https://pypi.org/project/pynetstring/0.5/) 为编解码能力参考，并用 [Twisted 25.5.0 NetstringReceiver](https://github.com/twisted/twisted/blob/twisted-25.5.0/src/twisted/protocols/basic.py) 交叉核对严格格式。实现为 MoonBit 原生代码；这里比较字节协议和处理能力，不包含 Python 运行时或 Twisted 传输层。

## 能力对照

| pynetstring 0.5 | MoonBit 接口 | 对照结果 |
|---|---|---|
| `encode(bytes)` | `encode(BytesView)` | 相同载荷生成相同的标准线格式，支持空载荷及任意二进制字节 |
| `encode(list)` | `encode_all(Array[BytesView])` | 批量能力已覆盖；本库拼接成一个 Bytes，Python 返回各帧组成的列表 |
| `decode(bytes)` | `decode(BytesView)` | 一次性读取所有完整帧，检查结尾截断；语法、长度限制见下表 |
| `Decoder.feed()` | `Decoder.feed()` | 可接收任意切块、拼接跨块载荷；本库通过回调交付完整帧，Python 返回列表 |
| `StreamingDecoder.feed()` | `StreamingDecoder.feed()` | 分段处理载荷；本库使用 `Begin(length)`、`Data(part)`、`End`，Python 用空字节串标记结束 |
| `pending()` | 两种解码器的 `pending()` | 查询有效流是否存在未完成帧；本库失败/关闭后返回 false，EOF 合法性以 `finish()` 为准 |
| `maxlen` | `max_len` | 都能在长度头超限时拒绝；默认值和零值含义不同 |
| `ParseError` 及子类 | `NetstringError(ErrorKind, Int64)` | 类型化错误包含类别和从当前流起点计算的零基字节偏移，不复制 Python 异常继承树 |

本库另外提供 Buffer 追加编码、线格式长度计算、独立长度头、首帧前缀读取、合法未完成前缀探测，以及 `feed_some` 暂停续喂、`finish`、`reset` 和回调重入保护。这些接口服务于流接入及资源控制，不改变 netstrings 线格式。

MoonBit 中也有其他分帧协议。例如 moonwire 使用带标识、版本、类型、三字节大端长度和校验和的固定头。需要与 pynetstring、Twisted 或 SCGI 的请求头交换标准 netstrings 时，接收方按十进制 ASCII 长度、冒号和终止逗号识别边界。[moonwire 帧格式](https://github.com/Han-Wentao/moonwire) · [SCGI 请求格式](https://python.ca/scgi/protocol.txt)

## 可观察差异

| 条件 | pynetstring 0.5 | 本库 |
|---|---|---|
| `01:a,` 等多余前导零 | 接受 | 按格式规范拒绝，与 Twisted 的严格规则一致 |
| 增量解码默认长度限制 | `maxlen=0`，不设上限 | 默认 99,999 字节 |
| 显式长度限制为 0 | 不设上限 | 仅接受空载荷；负值报 `InvalidLimit` |
| 一次性/前缀解码的默认上限 | 一次性解码不设上限；无对应前缀入口 | 默认 2,147,483,647，可显式调低 |
| 文本输入 | `str` 自动转换为 UTF-8 | 接收字节，由调用方选择文本编码 |
| 同次喂入包含有效帧及后续错误 | 异常使本次 `feed()` 不返回其结果列表 | 错误之前的完整帧已交给回调，调用方需处理这些已交付结果 |
| 流式帧结束 | 返回列表中的空字节串 | `End`；空帧为 `Begin(0)`、`End`，无空 `Data` |
| EOF 与失败恢复 | `decode()` 检查截断；增量类无独立 `finish/reset` 接口 | `finish()` 检查 EOF；长度、格式或 EOF 截断错误锁定，`reset()` 才开始新流 |

`encode_header` 与 `encoded_length` 可处理 UInt 范围的长度值；实际接收长度受 Int 上限和 `max_len` 限制。生成长度头不表示本库能够接收该范围内的任意大帧，双方须采用一致的接收限制。

需要返回一个连续 `Bytes` 时，完整线格式（含每帧的长度头和逗号）最多可表示 2,147,483,647 字节，实际可分配大小还取决于运行环境。大批次可在发送前分批，或逐帧发送长度头、载荷和逗号。

错误类别按触发条件对应：pynetstring 的 `TooLong` 对应本库 `TooLong`；`BadLength` 对应 `EmptyLength` 或 `InvalidByte`；`IncompleteString` 对应 `MissingComma` 或 `Truncated`。本库另有严格格式和生命周期错误 `LeadingZero`、`Closed`、`InvalidLimit`、`Reentrant`。这不是异常类型或错误优先级的一一兼容，例如 `decode(b"2147483648:")` 在本库先报 `TooLong`，在 pynetstring 0.5 中因没有收到完整载荷而报 `IncompleteString`。

## 接入边界

`Decoder` 在终止逗号通过校验后才交付帧；流式 `Data` 可能来自最终无效的帧，调用方应在 `End` 提交，出错时撤销当前帧的临时处理。`feed_some` 返回已消费的前缀长度，续喂时只传剩余后缀，库不会自动重放业务失败的帧。

本库不操作网络、文件或异步队列，也不判断载荷业务格式。`BytesView` 会保留底层 Bytes；单帧上限不约束调用方队列、累计输入或运行时总内存。具体示例和生命周期见[使用场景](USAGE.md)。

对标结论是核心编解码能力已覆盖并明确适配差异，不是全部 Python 类型、异常状态和输入行为完全相同。
