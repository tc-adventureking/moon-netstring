///|
/// Data may precede comma validation. Only End commits a frame.
#derive(Eq, @debug.Debug)
pub(all) enum Event {
  Begin(Int32)
  Data(BytesView)
  End
}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
priv enum Phase {
  Length
  Payload
  Comma
  Finished
  Failed(NetstringError)
}

///|
/// Transport-independent parser. It retains no payload bytes.
struct StreamingDecoder {
  max_len : Int32
  mut phase : Phase
  mut length : Int32
  mut digits : Int32
  mut remaining : Int32
  mut position : Int64
  mut busy : Bool
}

///|
/// A zero limit accepts empty frames only. Negative limits are rejected.
pub fn StreamingDecoder::new(
  max_len~ : Int32 = 99_999,
) -> StreamingDecoder raise NetstringError {
  if max_len < 0 {
    raise NetstringError(InvalidLimit, 0L)
  }
  {
    max_len,
    phase: Length,
    length: 0,
    digits: 0,
    remaining: 0,
    position: 0L,
    busy: false,
  }
}

///|
/// True when a partial frame has been consumed. Does not imply validity.
pub fn StreamingDecoder::pending(self : StreamingDecoder) -> Bool {
  match self.phase {
    Length => self.digits != 0
    Payload | Comma => true
    _ => false
  }
}

///|
/// The next unconsumed stream byte, relative to the last reset.
pub fn StreamingDecoder::offset(self : StreamingDecoder) -> Int64 {
  self.position
}

///|
fn StreamingDecoder::fail(
  self : StreamingDecoder,
  kind : ErrorKind,
) -> Unit raise NetstringError {
  let error = NetstringError(kind, self.position)
  self.phase = Failed(error)
  raise error
}

///| Deliver nonempty zero-copy views of chunk data. Never call this parser's

///|
/// mutating methods from a callback. Such calls raise Reentrant without mutation.
pub fn StreamingDecoder::feed(
  self : StreamingDecoder,
  chunk : BytesView,
  on_event : (Event) -> Unit,
) -> Unit raise NetstringError {
  if self.busy {
    raise NetstringError(Reentrant, self.position)
  }
  match self.phase {
    Failed(error) => raise error
    Finished => raise NetstringError(Closed, self.position)
    _ => ()
  }
  self.busy = true
  defer {
    self.busy = false
  }
  self.feed_inner(chunk, on_event)
}

///|
fn StreamingDecoder::feed_inner(
  self : StreamingDecoder,
  chunk : BytesView,
  on_event : (Event) -> Unit,
) -> Unit raise NetstringError {
  let mut i = 0
  while i < chunk.length() {
    match self.phase {
      Length => {
        let byte = chunk[i]
        if byte >= b'0' && byte <= b'9' {
          if self.digits > 0 && self.length == 0 {
            self.fail(LeadingZero)
          }
          let digit = byte.to_int() - 48
          if self.length > self.max_len / 10 ||
            (self.length == self.max_len / 10 && digit > self.max_len % 10) {
            self.fail(TooLong)
          }
          self.length = self.length * 10 + digit
          self.digits = self.digits + 1
          i = i + 1
          self.position = self.position + 1L
        } else if byte == b':' {
          if self.digits == 0 {
            self.fail(EmptyLength)
          }
          self.remaining = self.length
          self.phase = if self.remaining == 0 { Comma } else { Payload }
          i = i + 1
          self.position = self.position + 1L
          on_event(Begin(self.length))
        } else {
          self.fail(InvalidByte)
        }
      }
      Payload => {
        let available = chunk.length() - i
        let count = if self.remaining < available {
          self.remaining
        } else {
          available
        }
        let part = chunk[i:i + count]
        self.remaining = self.remaining - count
        i = i + count
        self.position = self.position + count.to_int64()
        if self.remaining == 0 {
          self.phase = Comma
        }
        on_event(Data(part))
      }
      Comma => {
        if chunk[i] != b',' {
          self.fail(MissingComma)
        }
        i = i + 1
        self.position = self.position + 1L
        self.phase = Length
        self.length = 0
        self.digits = 0
        on_event(End)
      }
      _ => abort("unreachable parser phase")
    }
  }
}

///| At a frame boundary closes successfully, and is then idempotent. A partial

///|
/// frame fails at EOF. Failed parsers keep their original error until reset.
pub fn StreamingDecoder::finish(
  self : StreamingDecoder,
) -> Unit raise NetstringError {
  if self.busy {
    raise NetstringError(Reentrant, self.position)
  }
  match self.phase {
    Failed(error) => raise error
    Finished => ()
    Length if self.digits == 0 => self.phase = Finished
    _ => self.fail(Truncated)
  }
}

///|
/// Reuse for a new stream; discard all old state and restart byte offsets at 0.
pub fn StreamingDecoder::reset(
  self : StreamingDecoder,
) -> Unit raise NetstringError {
  if self.busy {
    raise NetstringError(Reentrant, self.position)
  }
  self.phase = Length
  self.length = 0
  self.digits = 0
  self.remaining = 0
  self.position = 0L
}
