///|
const DEFAULT_HEADER_LIMIT : Int32 = 65_536

///|
const DEFAULT_BODY_LIMIT : Int64 = 67_108_864L

///|
let content_length_name : Bytes = b"CONTENT_LENGTH"

///|
let scgi_name : Bytes = b"SCGI"

///|
/// A raw SCGI header field. Names must be nonempty. Neither part may contain NUL.
#derive(Eq, @debug.Debug)
pub(all) struct Header {
  name : BytesView
  value : BytesView
}

///|
pub extend Header with Eq::{equal, not_equal}

///|
pub extend Header with @debug.Debug::{to_repr}

///|
/// A validated SCGI request head. The fields are kept in wire order.
#derive(@debug.Debug)
struct RequestHead {
  content_length : Int64
  fields : Map[Bytes, BytesView]
}

///|
pub extend RequestHead with @debug.Debug::{to_repr}

///|
/// An entire request. The body borrows the input passed to decode_request.
pub struct Request {
  head : RequestHead
  body : BytesView
}

///|
/// FramingError carries a wire offset. MalformedHeader carries an offset
/// within the netstring payload. InvalidField carries a caller field index.
/// TruncatedBody reports the number of missing bytes.
#derive(Eq, @debug.Debug)
pub(all) suberror RequestError {
  FramingError(@netstring.NetstringError)
  InvalidLimit
  MalformedHeader(Int32)
  ContentLengthMustBeFirst
  InvalidContentLength
  InvalidVersion
  DuplicateHeader(Bytes)
  BodyTooLarge(Int64)
  HeaderTooLarge(Int32)
  InvalidField(Int32)
  RequestTooLarge
  TruncatedHead(Int64)
  TruncatedBody(Int64)
  TrailingData(Int32)
  Reentrant
}

///|
pub extend RequestError with Eq::{equal, not_equal}

///|
pub extend RequestError with @debug.Debug::{to_repr}

///|
pub fn RequestHead::content_length(self : RequestHead) -> Int64 {
  self.content_length
}

///|
/// Look up a byte-exact header name, including the two required SCGI fields.
pub fn RequestHead::get(self : RequestHead, name : BytesView) -> BytesView? {
  self.fields.get(name.to_owned())
}

///|
/// Return the received fields in wire order.
pub fn RequestHead::headers(self : RequestHead) -> Array[Header] {
  let fields = []
  for name, value in self.fields {
    fields.push({ name: name[:], value, })
  }
  fields
}

///|
fn validate_limits(
  max_header_len : Int32,
  max_body_len : Int64,
) -> Unit raise RequestError {
  if max_header_len < 0 || max_body_len < 0L {
    raise InvalidLimit
  }
}

///|
fn find_terminator(
  header : BytesView,
  start : Int32,
) -> Int32 raise RequestError {
  for index in start..<header.length() {
    if header[index] == b'\x00' {
      return index
    }
  }
  raise MalformedHeader(header.length())
}

///|
fn read_content_length(
  value : BytesView,
  limit : Int64,
) -> Int64 raise RequestError {
  if value.length() == 0 {
    raise InvalidContentLength
  }
  let max_prefix = limit / 10L
  let max_digit = limit % 10L
  let mut length = 0L
  for byte in value {
    if byte < b'0' || byte > b'9' {
      raise InvalidContentLength
    }
    let digit = (byte.to_int() - 48).to_int64()
    if length > max_prefix || (length == max_prefix && digit > max_digit) {
      raise BodyTooLarge(limit)
    }
    length = length * 10L + digit
  }
  length
}

///|
fn parse_head(
  payload : BytesView,
  max_body_len : Int64,
) -> RequestHead raise RequestError {
  if payload.length() == 0 {
    raise ContentLengthMustBeFirst
  }
  // Keep one owned header instead of retaining the transport chunk behind it.
  let header = payload.to_owned()[:]
  let fields : Map[Bytes, BytesView] = Map([])
  let mut cursor = 0
  let mut content_length = 0L
  while cursor < header.length() {
    let name_end = find_terminator(header, cursor)
    if name_end == cursor {
      raise MalformedHeader(cursor)
    }
    let name = header[cursor:name_end]
    let value_start = name_end + 1
    let value_end = find_terminator(header, value_start)
    let value = header[value_start:value_end]
    if cursor == 0 {
      if name != content_length_name[:] {
        raise ContentLengthMustBeFirst
      }
      content_length = read_content_length(value, max_body_len)
    }
    // An SCGI name may start at any byte offset. Hash an owned byte key.
    let key = name.to_owned()
    if fields.contains(key) {
      raise DuplicateHeader(key)
    }
    fields[key] = value
    cursor = value_end + 1
  }
  if fields.get(scgi_name) != Some(b"1"[:]) {
    raise InvalidVersion
  }
  { content_length, fields, }
}

///|
/// Decode exactly one request. Limits are the netstring payload size and body
/// size in bytes. Incomplete and trailing data are reported as separate errors.
pub fn decode_request(
  input : BytesView,
  max_header_len~ : Int32 = DEFAULT_HEADER_LIMIT,
  max_body_len~ : Int64 = DEFAULT_BODY_LIMIT,
) -> Request raise RequestError {
  validate_limits(max_header_len, max_body_len)
  let (payload, header_end) = @netstring.decode_prefix(
    input,
    max_len=max_header_len,
  ) catch {
    error if error.kind() == @netstring.Truncated =>
      raise TruncatedHead(error.offset())
    error => raise FramingError(error)
  }
  let head = parse_head(payload, max_body_len)
  let actual_length = (input.length() - header_end).to_int64()
  let expected_length = head.content_length
  if actual_length < expected_length {
    raise TruncatedBody(expected_length - actual_length)
  }
  if actual_length > expected_length {
    raise TrailingData(header_end + expected_length.to_int())
  }
  { head, body: input[header_end:], }
}
