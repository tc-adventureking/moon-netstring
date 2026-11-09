///|
/// Exact wire length: decimal digits, colon, payload and comma. UInt input
/// prevents negative lengths. The result uses Int64 to avoid size overflow,
/// including when planning a payload larger than a contiguous Bytes value.
pub fn encoded_length(payload_length : UInt32) -> Int64 {
  let mut digits = 1
  let mut remaining = payload_length
  while remaining >= 10U {
    remaining = remaining / 10U
    digits = digits + 1
  }
  payload_length.to_int64() + digits.to_int64() + 2L
}
