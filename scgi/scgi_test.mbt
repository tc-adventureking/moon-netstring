///|
let reference_request : Bytes = b"70:CONTENT_LENGTH\x0027\x00SCGI\x001\x00REQUEST_METHOD\x00POST\x00REQUEST_URI\x00/deepthought\x00,What is the answer to life?"

///|
let reference_body : Bytes = b"What is the answer to life?"

///|
let empty_request : Bytes = b"24:CONTENT_LENGTH\x000\x00SCGI\x001\x00,"

///|
fn[T] assert_request_error(
  action : () -> T raise @scgi.RequestError,
  expected : @scgi.RequestError,
) -> Unit raise {
  try action() catch {
    error => assert_eq(error, expected)
  } noraise {
    _ => fail("expected an SCGI error")
  }
}

///|
test "wire matches the SCGI specification example" {
  let fields : Array[@scgi.Header] = [
    { name: b"REQUEST_METHOD"[:], value: b"POST"[:], },
    { name: b"REQUEST_URI"[:], value: b"/deepthought"[:], },
  ]
  assert_eq(
    @scgi.encode_request(fields[:], reference_body[:]),
    reference_request,
  )
  let request = @scgi.decode_request(reference_request[:])
  assert_eq(request.body.to_owned(), reference_body)
  assert_eq(request.head.content_length(), 27L)
  assert_eq(request.head.get(b"REQUEST_METHOD"[:]), Some(b"POST"[:]))
  assert_eq(request.head.get(b"REQUEST_URI"[:]), Some(b"/deepthought"[:]))
  assert_eq(request.head.get(b"request_uri"[:]), None)
  assert_eq(request.head.headers(), [
    { name: b"CONTENT_LENGTH"[:], value: b"27"[:], },
    { name: b"SCGI"[:], value: b"1"[:], },
    fields[0],
    fields[1],
  ])
}

///|
test "field names, values, and body round-trip raw bytes" {
  let fields : Array[@scgi.Header] = [
    { name: b"\xffKEY"[:], value: b"\x80\xfe:,"[:], },
    { name: b"EMPTY"[:], value: b""[:], },
  ]
  let body = b"\x00\xff:,\x80"
  let wire = @scgi.encode_request(fields[:], body[:])
  let request = @scgi.decode_request(wire[:])
  assert_eq(request.head.get(fields[0].name), Some(fields[0].value))
  assert_eq(request.head.get(fields[1].name), Some(b""[:]))
  assert_eq(request.body.to_owned(), body)
}

///|
test "encode and look up field names sliced at different byte offsets" {
  for offset in 1..<5 {
    let storage = b"xxxxREQUEST_METHOD"
    let key = storage[offset:offset + 8]
    let fields : Array[@scgi.Header] = [{ name: key, value: b"ok"[:] }]
    let wire = @scgi.encode_request(fields[:], b""[:])
    let request = @scgi.decode_request(wire[:])
    assert_eq(request.head.get(key), Some(b"ok"[:]))
    assert_eq(request.head.headers()[2].name, key)
  }
}

///|
test "decodes a binary POST forwarded by nginx" {
  // Captured from nginx 1.28.3 with scgi_pass on a loopback connection.
  let chunks : Array[Bytes] = [
    b"237:CONTENT_LENGTH\x008\x00SCGI\x001\x00REQUEST_METHOD\x00POST\x00", b"REQUEST_URI\x00/scgi/verify?binary=1\x00CONTENT_TYPE\x00application/octet-stream\x00",
    b"HTTP_HOST\x00127.0.0.1:32867\x00HTTP_ACCEPT_ENCODING\x00identity\x00", b"HTTP_CONTENT_LENGTH\x008\x00HTTP_CONTENT_TYPE\x00application/octet-stream\x00,\x00\xff",
    b",:\r\n\x80\x00",
  ]
  let decoder = @scgi.RequestDecoder::new()
  let body = @buffer.Buffer()
  let mut request_head : @scgi.RequestHead? = None
  let on_event = fn(event : @scgi.RequestEvent) {
    match event {
      Head(head) => request_head = Some(head)
      Body(part) => body.write_bytesview(part)
      End => ()
    }
  }
  for chunk in chunks {
    assert_eq(decoder.feed(chunk[:], on_event), chunk.length())
  }
  decoder.finish()
  guard request_head is Some(head) else { fail("missing SCGI request head") }
  assert_eq(head.content_length(), 8L)
  assert_eq(head.get(b"REQUEST_METHOD"[:]), Some(b"POST"[:]))
  assert_eq(head.get(b"REQUEST_URI"[:]), Some(b"/scgi/verify?binary=1"[:]))
  assert_eq(head.get(b"CONTENT_TYPE"[:]), Some(b"application/octet-stream"[:]))
  assert_eq(body.to_bytes(), b"\x00\xff,:\r\n\x80\x00")
}

///|
test "decoder consumes one request across every two-chunk split" {
  for split in 0..<=reference_request.length() {
    let decoder = @scgi.RequestDecoder::new()
    let body = @buffer.Buffer()
    let mut head_count = 0
    let mut completed = 0
    let mut content_length = 0L
    let on_event = fn(event : @scgi.RequestEvent) {
      match event {
        Head(head) => {
          head_count += 1
          content_length = head.content_length()
        }
        Body(part) => body.write_bytesview(part)
        End => completed += 1
      }
    }
    assert_eq(decoder.feed(reference_request[:split], on_event), split)
    assert_eq(
      decoder.feed(reference_request[split:], on_event),
      reference_request.length() - split,
    )
    decoder.finish()
    assert_true(decoder.is_complete())
    assert_eq(head_count, 1)
    assert_eq(content_length, 27L)
    assert_eq(body.to_bytes(), reference_body)
    assert_eq(completed, 1)
  }
}

///|
test "empty body emits Head and End and leaves trailing bytes unconsumed" {
  let wire = b"24:CONTENT_LENGTH\x000\x00SCGI\x001\x00,extra"
  let decoder = @scgi.RequestDecoder::new(max_body_len=0L)
  let events = []
  let on_event = fn(event : @scgi.RequestEvent) {
    match event {
      Head(_) => events.push("head")
      Body(_) => events.push("body")
      End => events.push("end")
    }
  }
  let consumed = decoder.feed(wire[:], on_event)
  assert_eq(consumed, empty_request.length())
  assert_eq(wire[consumed:].to_owned(), b"extra")
  assert_eq(decoder.feed(wire[consumed:], on_event), 0)
  decoder.finish()
  decoder.finish()
  assert_eq(events, ["head", "end"])
}

///|
test "final body chunk is capped at CONTENT_LENGTH" {
  let decoder = @scgi.RequestDecoder::new()
  let head = @scgi.encode_head([], 3L)
  let body = @buffer.Buffer()
  let mut ended = false
  let on_event = fn(event : @scgi.RequestEvent) {
    match event {
      Head(_) => ()
      Body(part) => body.write_bytesview(part)
      End => ended = true
    }
  }
  assert_eq(decoder.feed(head[:], on_event), head.length())
  assert_false(ended)
  assert_eq(decoder.feed(b"a"[:], on_event), 1)
  assert_eq(decoder.feed(b"\xff,extra"[:], on_event), 2)
  decoder.finish()
  assert_true(ended)
  assert_eq(body.to_bytes(), b"a\xff,")
}

///|
test "one-shot decoding rejects both truncation and overrun" {
  assert_request_error(() => @scgi.decode_request(b""[:]), TruncatedHead(0L))
  assert_request_error(
    () => @scgi.decode_request(empty_request[:27]),
    TruncatedHead(27L),
  )
  assert_request_error(
    () => @scgi.decode_request(reference_request[:95]),
    TruncatedBody(6L),
  )
  assert_request_error(
    () => @scgi.decode_request(b"24:CONTENT_LENGTH\x000\x00SCGI\x001\x00,x"[:]),
    TrailingData(28),
  )
}

///|
test "streaming EOF agrees with one-shot decoding at each incomplete split" {
  let header_end = 74
  for split in 0..<reference_request.length() {
    let decoder = @scgi.RequestDecoder::new()
    let input = reference_request[:split]
    assert_eq(decoder.feed(input, fn(_) { () }), split)
    let expected : @scgi.RequestError = if split < header_end {
      TruncatedHead(split.to_int64())
    } else {
      TruncatedBody((reference_request.length() - split).to_int64())
    }
    assert_request_error(() => decoder.finish(), expected)
    assert_request_error(() => @scgi.decode_request(input), expected)
  }
}

///|
test "required fields, version, duplicates and NUL framing are checked" {
  let cases : Array[(Bytes, @scgi.RequestError)] = [
    (b"", ContentLengthMustBeFirst),
    (b"SCGI\x001\x00CONTENT_LENGTH\x000\x00", ContentLengthMustBeFirst),
    (b"CONTENT_LENGTH\x000\x00", InvalidVersion),
    (b"CONTENT_LENGTH\x000\x00SCGI\x002\x00", InvalidVersion),
    (b"CONTENT_LENGTH\x000\x00SCGI\x001", MalformedHeader(23)),
    (b"CONTENT_LENGTH\x000\x00SCGI\x001\x00\x00value\x00", MalformedHeader(24)),
    (
      b"CONTENT_LENGTH\x000\x00SCGI\x001\x00X\x001\x00X\x002\x00",
      DuplicateHeader(b"X"),
    ),
    (
      b"CONTENT_LENGTH\x000\x00SCGI\x001\x00SCGI\x001\x00",
      DuplicateHeader(b"SCGI"),
    ),
  ]
  for entry in cases {
    let (payload, expected) = entry
    let wire = @netstring.encode(payload[:])
    assert_request_error(() => @scgi.decode_request(wire[:]), expected)
  }
}

///|
test "content length accepts ASCII digits and rejects invalid values" {
  for
    payload in [
      b"CONTENT_LENGTH\x00\x00SCGI\x001\x00", b"CONTENT_LENGTH\x00-1\x00SCGI\x001\x00",
      b"CONTENT_LENGTH\x00 1\x00SCGI\x001\x00", b"CONTENT_LENGTH\x00\xff\x00SCGI\x001\x00",
    ] {
    let wire = @netstring.encode(payload[:])
    assert_request_error(
      () => @scgi.decode_request(wire[:]),
      InvalidContentLength,
    )
  }
  let request = @scgi.decode_request(
    b"26:CONTENT_LENGTH\x00000\x00SCGI\x001\x00,"[:],
  )
  assert_eq(request.head.content_length(), 0L)
  assert_eq(request.body.length(), 0)
}

///|
test "header and body limits are enforced at the exact boundary" {
  let request = @scgi.decode_request(
    empty_request[:],
    max_header_len=24,
    max_body_len=0L,
  )
  assert_eq(request.head.content_length(), 0L)
  assert_request_error(
    () => @scgi.decode_request(empty_request[:], max_header_len=23),
    FramingError(@netstring.NetstringError(@netstring.TooLong, 1L)),
  )
  assert_request_error(
    () => @scgi.decode_request(reference_request[:], max_body_len=26L),
    BodyTooLarge(26L),
  )
  assert_eq(
    @scgi.decode_request(reference_request[:], max_body_len=27L).body.to_owned(),
    reference_body,
  )
}

///|
test "length overflow fails at the header with no body allocation" {
  let payload = b"CONTENT_LENGTH\x009223372036854775808\x00SCGI\x001\x00"
  let wire = @netstring.encode(payload[:])
  let limit = 9_223_372_036_854_775_807L
  let decoder = @scgi.RequestDecoder::new(max_body_len=limit)
  assert_request_error(
    () => decoder.feed(wire[:], fn(_) { abort("invalid header was emitted") }),
    BodyTooLarge(limit),
  )
  let valid_head = @scgi.encode_head([], limit)
  let valid_decoder = @scgi.RequestDecoder::new(max_body_len=limit)
  assert_eq(
    valid_decoder.feed(valid_head[:], fn(_) { () }),
    valid_head.length(),
  )
  assert_request_error(() => valid_decoder.finish(), TruncatedBody(limit))
}

///|
test "framing faults report their wire offset and remain latched" {
  let decoder = @scgi.RequestDecoder::new()
  let wire = b"24:CONTENT_LENGTH\x000\x00SCGI\x001\x00;"
  let mut events = 0
  let on_event = fn(_) { events += 1 }
  let expected : @scgi.RequestError = FramingError(
    @netstring.NetstringError(@netstring.MissingComma, 27L),
  )
  assert_request_error(() => decoder.feed(wire[:], on_event), expected)
  assert_request_error(() => decoder.feed(empty_request[:], on_event), expected)
  assert_eq(events, 0)
}

///|
test "EOF during a body reports the remaining bytes and stays failed" {
  let decoder = @scgi.RequestDecoder::new()
  assert_eq(decoder.feed(reference_request[:75], fn(_) { () }), 75)
  assert_request_error(() => decoder.finish(), TruncatedBody(26L))
  assert_request_error(
    () => decoder.feed(reference_request[75:], fn(_) { () }),
    TruncatedBody(26L),
  )
  assert_false(decoder.is_complete())
}

///|
test "callbacks cannot feed or close the same decoder recursively" {
  let decoder = @scgi.RequestDecoder::new()
  let errors : Array[@scgi.RequestError] = []
  let consumed = decoder.feed(empty_request[:], fn(event) {
    match event {
      Head(_) => {
        let _ = decoder.feed(b""[:], fn(_) { () }) catch {
          error => {
            errors.push(error)
            0
          }
        }
        decoder.finish() catch {
          error => errors.push(error)
        }
      }
      _ => ()
    }
  })
  assert_eq(consumed, empty_request.length())
  decoder.finish()
  assert_eq(errors, [Reentrant, Reentrant])
}

///|
test "encoder rejects duplicate, reserved and invalid fields" {
  let reserved : @scgi.Header = { name: b"SCGI"[:], value: b"1"[:], }
  let field : @scgi.Header = { name: b"X"[:], value: b"1"[:], }
  let cases : Array[(Array[@scgi.Header], @scgi.RequestError)] = [
    ([reserved], DuplicateHeader(b"SCGI")),
    ([field, field], DuplicateHeader(b"X")),
    ([{ name: b""[:], value: b"1"[:], }], InvalidField(0)),
    ([{ name: b"X\x00Y"[:], value: b"1"[:], }], InvalidField(0)),
    ([{ name: b"X"[:], value: b"1\x002"[:], }], InvalidField(0)),
  ]
  for entry in cases {
    let (fields, expected) = entry
    assert_request_error(() => @scgi.encode_head(fields[:], 0L), expected)
  }
}

///|
test "split encoder and empty request respect the header limit" {
  assert_eq(@scgi.encode_head([], 0L, max_header_len=24), empty_request)
  assert_eq(@scgi.encode_request([], b""[:]), empty_request)
  assert_request_error(
    () => @scgi.encode_head([], 0L, max_header_len=23),
    HeaderTooLarge(23),
  )
  assert_request_error(() => @scgi.encode_head([], -1L), InvalidContentLength)
  assert_request_error(
    () => @scgi.RequestDecoder::new(max_body_len=-1L),
    InvalidLimit,
  )
}
