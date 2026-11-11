// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// Derived property of one code point (RFC 5892 3) as far as an already mapped,
/// NFC-normalised label needs it. `Unassigned` is folded into `Disallowed`
/// because neither value may appear in a label.
priv enum FormatIdnaProperty {
  Pvalid
  ContextJ
  ContextO
  Disallowed
}

///|
/// IDNA2008 validity of one label, applied on top of UTS #46 processing. The
/// UTS #46 mapping table behind `@idna` marks punctuation, symbols and the
/// RFC 5892 2.6 exceptions valid, so a ToASCII-only pipeline accepts labels
/// that IDNA2008 forbids; only the derived property and the Appendix A
/// contextual rules can reject them.
fn format_idna2008_label(label : StringView) -> Bool {
  if label.is_empty() {
    return false
  }
  let chars = label.to_array()
  let mut arabic_indic = false
  let mut extended_arabic_indic = false
  let mut kana_or_han = false
  for index in 0..<chars.length() {
    let ch = chars[index]
    match format_idna_property(ch) {
      Disallowed => return false
      ContextJ | ContextO | Pvalid => ()
    }
    if ch is ('\u{0660}'..<='\u{0669}') {
      arabic_indic = true
    }
    if ch is ('\u{06F0}'..<='\u{06F9}') {
      extended_arabic_indic = true
    }
    if format_idna_kana_or_han(ch) {
      kana_or_han = true
    }
  }
  // RFC 5892 Appendix A.8 / A.9: the two digit blocks must not be mixed.
  if arabic_indic && extended_arabic_indic {
    return false
  }
  for index in 0..<chars.length() {
    if format_idna_property(chars[index]) is ContextO &&
      !format_idna_context(chars, index, kana_or_han~) {
      return false
    }
  }
  true
}

///|
/// RFC 5892 3 derived-property calculation, in the order of that section. Two
/// inputs the section uses are not reproduced: `Unstable` (2.2) needs NFKC plus
/// case folding of every code point, and uppercase code points never reach this
/// check because UTS #46 has already mapped them to lowercase.
fn format_idna_property(ch : Char) -> FormatIdnaProperty {
  if format_idna_exception(ch) is Some(property) {
    return property
  }
  // 2.5 LDH.
  if ch is ('-' | '0'..<='9' | 'a'..<='z') {
    return Pvalid
  }
  // 2.8 JoinControl. `@idna` has already applied the Appendix A.1/A.2 rules.
  if ch is ('\u{200C}' | '\u{200D}') {
    return ContextJ
  }
  // 2.3 IgnorableProperties.
  if @ucd.is_default_ignorable_code_point(ch) ||
    @ucd.is_white_space(ch) ||
    format_is_noncharacter(ch) {
    return Disallowed
  }
  // 2.4 IgnorableBlocks: Combining Diacritical Marks for Symbols, Musical
  // Symbols, Ancient Greek Musical Notation.
  if ch
    is ('\u{20D0}'..<='\u{20FF}'
    | '\u{1D100}'..<='\u{1D1FF}'
    | '\u{1D200}'..<='\u{1D24F}') {
    return Disallowed
  }
  // 2.9 OldHangulJamo.
  if @ucd.hangul_syllable_type(ch) is (LeadingJamo | VowelJamo | TrailingJamo) {
    return Disallowed
  }
  // 2.1 LetterDigits.
  if @ucd.general_category(ch) is (Ll | Lu | Lo | Nd | Lm | Mn | Mc) {
    return Pvalid
  }
  Disallowed
}

///|
/// RFC 5892 2.6 Exceptions: the code points whose derived property cannot be
/// computed from the core property values, so the table decides.
fn format_idna_exception(ch : Char) -> FormatIdnaProperty? {
  match ch.to_int() {
    0x00DF | 0x03C2 | 0x06FD | 0x06FE | 0x0F0B | 0x3007 => Some(Pvalid)
    0x00B7
    | 0x0375
    | 0x05F3
    | 0x05F4
    | 0x0660..<=0x0669
    | 0x06F0..<=0x06F9
    | 0x30FB => Some(ContextO)
    0x0640 | 0x07FA | 0x302E | 0x302F | 0x3031..<=0x3035 | 0x303B =>
      Some(Disallowed)
    _ => None
  }
}

///|
/// RFC 5892 Appendix A.3-A.7 contextual rules. The Arabic-Indic digit rules
/// (A.8/A.9) are decided once per label, not per position.
fn format_idna_context(
  chars : Array[Char],
  index : Int32,
  kana_or_han~ : Bool,
) -> Bool {
  let ch = chars[index]
  if ch is '\u{00B7}' {
    // A.3: MIDDLE DOT only between two 'l'.
    return index > 0 &&
      index + 1 < chars.length() &&
      chars[index - 1] == 'l' &&
      chars[index + 1] == 'l'
  }
  if ch is '\u{0375}' {
    // A.4: GREEK KERAIA must be followed by Greek.
    return index + 1 < chars.length() && format_idna_greek(chars[index + 1])
  }
  if ch is ('\u{05F3}' | '\u{05F4}') {
    // A.5/A.6: GERESH and GERSHAYIM must be preceded by Hebrew.
    return index > 0 && format_idna_hebrew(chars[index - 1])
  }
  if ch is '\u{30FB}' {
    // A.7: KATAKANA MIDDLE DOT requires Hiragana, Katakana or Han in the label.
    return kana_or_han
  }
  // A.8/A.9: nothing positional left, the digit-block mixing rule decides.
  true
}

///|
/// `Script(cp).eq.Greek` approximated by the Greek and Coptic plus Greek
/// Extended blocks, which is what the rule needs to recognise.
fn format_idna_greek(ch : Char) -> Bool {
  ch is ('\u{0370}'..<='\u{03FF}' | '\u{1F00}'..<='\u{1FFF}')
}

///|
/// `Script(cp).eq.Hebrew` approximated by the Hebrew block plus the Hebrew
/// presentation forms.
fn format_idna_hebrew(ch : Char) -> Bool {
  ch is ('\u{0590}'..<='\u{05FF}' | '\u{FB1D}'..<='\u{FB4F}')
}

///|
/// `Script(cp).in.{Hiragana, Katakana, Han}` approximated by the Hiragana,
/// Katakana, Katakana Phonetic Extensions, halfwidth Katakana, CJK Unified
/// Ideographs (all three blocks) and CJK Compatibility Ideographs blocks.
/// U+30FB KATAKANA MIDDLE DOT is excluded because its own Script is Common,
/// which is exactly what the A.7 rule relies on.
fn format_idna_kana_or_han(ch : Char) -> Bool {
  ch
  is ('\u{3040}'..<='\u{309F}'
  | '\u{30A0}'..<='\u{30FA}'
  | '\u{30FC}'..<='\u{30FF}'
  | '\u{31F0}'..<='\u{31FF}'
  | '\u{3400}'..<='\u{4DBF}'
  | '\u{4E00}'..<='\u{9FFF}'
  | '\u{F900}'..<='\u{FAFF}'
  | '\u{FF66}'..<='\u{FF9D}'
  | '\u{20000}'..<='\u{2FA1F}')
}

///|
/// `Noncharacter_Code_Point`, which RFC 5892 2.3 adds to IgnorableProperties.
fn format_is_noncharacter(ch : Char) -> Bool {
  let code = ch.to_int()
  (code >= 0xFDD0 && code <= 0xFDEF) || (code & 0xFFFE) == 0xFFFE
}
