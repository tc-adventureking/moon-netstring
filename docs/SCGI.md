# SCGI 请求编解码

`tc-adventureking/netstring/scgi` 处理 Web 服务器通过 SCGI 转发给应用的请求。它复用库的 netstring 分帧，并根据头部的 `CONTENT_LENGTH` 读取二进制正文。调用方负责网络读写及生成 CGI 响应。[SCGI 规范](https://python.ca/scgi/protocol.txt)

## 编码和解码完整请求

在 `moon.pkg` 中导入 `"tc-adventureking/netstring/scgi" @scgi`。以下示例可在包含 `scgi` 子包的源码版本中运行。

```moonbit
let headers : Array[@scgi.Header] = [
  { name: b"REQUEST_METHOD"[:], value: b"POST"[:] },
  { name: b"REQUEST_URI"[:], value: b"/upload"[:] },
]
let body = b"part:\x00,\xff"
let wire = @scgi.encode_request(headers[:], body[:])
let request = @scgi.decode_request(wire[:])
assert_eq(request.head.get(b"REQUEST_URI"[:]), Some(b"/upload"[:]))
assert_eq(request.body.to_owned(), body)
```

编码器生成位于第一项的 `CONTENT_LENGTH` 和 `SCGI=1`。附加字段按传入顺序编码，重复字段和包含 NUL 的字段会被拒绝。解码器校验这两个必填项以及正文长度，允许空字段值和空正文。`decode_request` 要求输入恰好包含一个完整请求。

## 分块传输

- 发送时，`encode_head(headers[:], content_length)` 生成完整的 netstring 请求头，随后可分块写出指定长度的原始正文。
- 接收时，给每个请求创建一个 `RequestDecoder`，按输入顺序调用 `feed`。回调先收到 `Head`，随后收到若干 `Body` 片段，读完声明的正文后收到 `End`。
- `feed` 返回本块消耗的字节数，请求结束后的剩余字节由调用方处理。`finish` 检查 EOF，遇到截断时报告缺失的头部或正文。需要完整请求才能提交的操作可以等到 `End`。
- 解码默认限制头部载荷为 64 KiB，正文为 64 MiB，分别通过 `max_header_len` 和 `max_body_len` 调整。流式解码器只保留解析状态和待校验的头部。要长期保存较大输入块里的小正文片段，可以用 `to_owned()` 复制。

## 验证

```bash
moon test scgi
moon run examples/scgi_request
```

回归测试逐字节比对 SCGI 规范的请求样例，遍历该请求的所有两块切分位置与提前 EOF 位置，并覆盖字段重复、非法长度、长度溢出和二进制正文。

回归测试还包含一份 Nginx 1.28.3 通过 `scgi_pass` 转发的 POST 请求。在本地回环联调中，MoonBit 解码器读出了请求头和全部 8 字节正文，HTTP 客户端收到了 201 响应及原样返回的二进制正文。
