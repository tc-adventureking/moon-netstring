///|
fn write_digits(output : @buffer.Buffer, value : UInt32) -> Unit {
  // A UInt32 has at most ten decimal digits.
  if value >= 10U {
    write_digits(output, value / 10U)
  }
  output.write_byte((48U + value % 10U).to_byte())
}

///|
fn write_header(output : @buffer.Buffer, payload_length : UInt32) -> Unit {
  write_digits(output, payload_length)
  output.write_byte(b':')
}

///|
fn wire_buffer(size : Int64) -> @buffer.Buffer {
  if size > 2_147_483_647L {
    abort("netstring output exceeds maximum Bytes length")
  }
  @buffer.Buffer(size_hint=size.to_int())
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
/// The caller's buffer must have room within the Int32 indexing limit for
/// the complete frame, including the length header and comma.
pub fn encode_to(output : @buffer.Buffer, payload : BytesView) -> Unit {
  write_header(output, payload.length().reinterpret_as_uint())
  output.write_bytes(payload)
  output.write_byte(b',')
}

///|
/// Encode one binary payload as decimal-length:payload,.
/// Aborts if the complete frame cannot fit in an Int32-indexed Bytes.
pub fn encode(payload : BytesView) -> Bytes {
  let size = encoded_length(payload.length().reinterpret_as_uint())
  let output = wire_buffer(size)
  encode_to(output, payload)
  output.to_bytes()
}

///|
/// Concatenate the encodings of an ordered batch of payloads.
/// Aborts before allocation if the combined wire size exceeds Int32's maximum.
pub fn encode_all(payloads : Array[BytesView]) -> Bytes {
  let mut size = 0L
  for payload in payloads {
    size += encoded_length(payload.length().reinterpret_as_uint())
  }
  let output = wire_buffer(size)
  for payload in payloads {
    encode_to(output, payload)
  }
  output.to_bytes()
}
