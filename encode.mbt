///|
fn write_header(output : @buffer.Buffer, payload_length : UInt32) -> Unit {
  output.write_string_utf8(payload_length.to_string()[:])
  output.write_byte(b':')
}

///|
/// Encode only the decimal length and colon. Send this header, exactly
/// payload_length payload bytes, then a comma to avoid copying a whole frame.
/// This UInt-sized sender may declare more than the local Int-sized decoder
/// accepts; respect the receiver's configured limit when interoperating.
pub fn encode_header(payload_length : UInt32) -> Bytes {
  let output = @buffer.Buffer(size_hint=11)
  write_header(output, payload_length)
  output.to_bytes()
}

///|
/// Append one netstring. Length counts payload bytes, not text characters.
pub fn encode_to(output : @buffer.Buffer, payload : BytesView) -> Unit {
  write_header(output, payload.length().reinterpret_as_uint())
  output.write_bytes(payload)
  output.write_byte(b',')
}

///|
/// Encode one binary payload as decimal-length:payload,.
pub fn encode(payload : BytesView) -> Bytes {
  let size = encoded_length(payload.length().reinterpret_as_uint())
  // A contiguous builder is Int-indexed even though size planning is Int64.
  let hint = if size <= 2_147_483_647L { size.to_int() } else { 0 }
  let output = @buffer.Buffer(size_hint=hint)
  encode_to(output, payload)
  output.to_bytes()
}

///|
/// Concatenate the encodings of an ordered batch of payloads.
pub fn encode_all(payloads : Array[BytesView]) -> Bytes {
  let output = @buffer.Buffer()
  for payload in payloads {
    encode_to(output, payload)
  }
  output.to_bytes()
}
