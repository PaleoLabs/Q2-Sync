//
//  Pluralize.swift
//  Q2-Sync
//
//  PURPOSE
//  One place for "1 song" / "12 songs" wording, so messages never say
//  "1 songs".
//

import Foundation

/// e.g. `pluralized(1, "song")` → "1 song"; `pluralized(12, "song")` → "12 songs".
/// Only for regular nouns that add an "s" (song, playlist, album, file…).
func pluralized(_ n: Int, _ noun: String) -> String {
    "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
}
