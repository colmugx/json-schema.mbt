// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
// Normalize the `General_Category=`/`gc=` property-name prefix. The engine
// resolves bare General_Category short/long value aliases itself and rejects
// everything else (scripts, binary properties, loose matching) as a typed
// compile error. Backreference, lookaround and shorthand behavior no longer
// needs adapter shims: upstream implements them natively as of 0.3.6.
#deprecated("Temporary General_Category normalization: recheck moonbitlang/regexp before removing", skip_current_package=true)
fn unicode_property(
  pattern : String,
  start : Int32,
) -> (String, Int32) raise PatternError {
  guard start + 2 < pattern.length() && pattern[start + 2] == '{' else {
    raise NotSupported("malformed Unicode property escape")
  }
  let mut end = start + 3
  while end < pattern.length() && pattern[end] != '}' {
    end += 1
  }
  guard end < pattern.length() else {
    raise NotSupported("unterminated Unicode property escape")
  }
  let name = pattern[start + 3:end].to_owned()
  let bare = if name.has_prefix("General_Category=") {
    name[17:].to_owned()
  } else if name.has_prefix("gc=") {
    name[3:].to_owned()
  } else {
    name
  }
  let negated = pattern[start + 1] == 'P'
  ("\\" + (if negated { "P" } else { "p" }) + "{" + bare + "}", end + 1)
}
