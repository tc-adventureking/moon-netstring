///|
/// The reason parsing failed. Offsets point to a byte, or EOF for Truncated.
#derive(Eq, @debug.Debug)
pub(all) enum ErrorKind {
  EmptyLength
  LeadingZero
  InvalidByte
  TooLong
  MissingComma
  Truncated
  Closed
  InvalidLimit
  Reentrant
}

///|
pub extend ErrorKind with Eq::{equal, not_equal}

///|
pub extend ErrorKind with @debug.Debug::{to_repr}

///|
/// A stable error kind and an absolute zero-based stream byte offset.
#derive(Eq, @debug.Debug)
pub(all) suberror NetstringError {
  NetstringError(ErrorKind, Int64)
}

///|
pub extend NetstringError with Eq::{equal, not_equal}

///|
pub extend NetstringError with @debug.Debug::{to_repr}

///|
pub fn NetstringError::kind(self : NetstringError) -> ErrorKind {
  let NetstringError(kind, _) = self
  kind
}

///|
pub fn NetstringError::offset(self : NetstringError) -> Int64 {
  let NetstringError(_, offset) = self
  offset
}
