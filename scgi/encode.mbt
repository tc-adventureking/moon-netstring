///|
fn has_nul(input : BytesView) -> Bool {
  for byte in input {
    if byte == b'\x00' {
      return true
    }
  }
  false
}

///|
fn Header::wire_size(self : Header) -> Int64 {
  self.name.length().to_int64() + self.value.length().to_int64() + 2L
}

///|
fn Header::write_to(self : Header, output : @buffer.Buffer) -> Unit {
  output.write_bytes(self.name)
  output.write_byte(b'\x00')
  output.write_bytes(self.value)
  output.write_byte(b'\x00')
}

///|
fn request_buffer(size : Int64) -> @buffer.Buffer raise RequestError {
  if size > 2_147_483_647L {
    raise RequestTooLarge
  }
  @buffer.Buffer(size_hint=size.to_int())
}

///|
/// Encode the netstring request head for split writes. Send exactly
/// content_length raw body bytes immediately after the returned head.
/// The required fields are generated in addition to the supplied fields.
pub fn encode_head(
  headers : ArrayView[Header],
  content_length : Int64,
  max_header_len~ : Int32 = DEFAULT_HEADER_LIMIT,
) -> Bytes raise RequestError {
  if max_header_len < 0 {
    raise InvalidLimit
  }
  if content_length < 0L {
    raise InvalidContentLength
  }
  let length_field : Header = {
    name: content_length_name[:],
    value: @utf8.encode(content_length.to_string())[:],
  }
  let version_field : Header = { name: scgi_name[:], value: b"1"[:], }
  let limit = max_header_len.to_int64()
  let mut size = length_field.wire_size() + version_field.wire_size()
  if size > limit {
    raise HeaderTooLarge(max_header_len)
  }
  let seen : Map[Bytes, Unit] = Map([])
  seen[content_length_name] = ()
  seen[scgi_name] = ()
  for index, field in headers {
    size += field.wire_size()
    if size > limit {
      raise HeaderTooLarge(max_header_len)
    }
    if field.name.length() == 0 || has_nul(field.name) || has_nul(field.value) {
      raise InvalidField(index)
    }
    let key = field.name.to_owned()
    if seen.contains(key) {
      raise DuplicateHeader(key)
    }
    seen[key] = ()
  }
  let payload_length = size.to_int().reinterpret_as_uint()
  let output = request_buffer(@netstring.encoded_length(payload_length))
  output.write_bytes(@netstring.encode_header(payload_length))
  length_field.write_to(output)
  version_field.write_to(output)
  for field in headers {
    field.write_to(output)
  }
  output.write_byte(b',')
  output.to_bytes()
}

///|
/// Encode an entire request, computing CONTENT_LENGTH from the binary body.
pub fn encode_request(
  headers : ArrayView[Header],
  body : BytesView,
  max_header_len~ : Int32 = DEFAULT_HEADER_LIMIT,
) -> Bytes raise RequestError {
  let body_length = body.length().to_int64()
  let head = encode_head(headers, body_length, max_header_len~)
  let output = request_buffer(head.length().to_int64() + body_length)
  output.write_bytes(head)
  output.write_bytes(body)
  output.to_bytes()
}
