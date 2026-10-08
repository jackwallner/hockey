#!/usr/bin/env swift
// Converts the bundled players-historical.json into a binary property list.
// PropertyListSerialization decode is ~2–3× faster than JSONSerialization on equivalent payloads,
// and binary plists are smaller on disk than indented JSON.
//
// Strips NSNull (plist disallows it) and converts ISO8601 date strings at known date keys
// into native Date objects so PropertyListDecoder can decode them with its default strategy
// (it has no dateDecodingStrategy on iOS — date types must be native in the plist).
//
// Run from repo root:
//   swift scripts/convert_historical_to_plist.swift
//   swift scripts/convert_historical_to_plist.swift players-current

import Foundation

let resourceName = CommandLine.arguments.dropFirst().first ?? "players-historical"
let input = "StatScout/Data/\(resourceName).json"
let output = "StatScout/Data/\(resourceName).plist"

// Keys whose string values are ISO8601 timestamps in the source JSON.
let dateKeys: Set<String> = ["updated_at", "date"]

let isoWithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseDate(_ s: String) -> Date? {
    isoWithFraction.date(from: s) ?? isoPlain.date(from: s)
}

func convert(_ obj: Any, parentKey: String? = nil) -> Any? {
    if obj is NSNull { return nil }
    if let dict = obj as? [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict {
            if let cleaned = convert(v, parentKey: k) {
                out[k] = cleaned
            }
        }
        return out
    }
    if let arr = obj as? [Any] {
        return arr.compactMap { convert($0, parentKey: parentKey) }
    }
    if let s = obj as? String, let key = parentKey, dateKeys.contains(key) {
        return parseDate(s) ?? s
    }
    return obj
}

let url = URL(fileURLWithPath: input)
let outURL = URL(fileURLWithPath: output)

let start = Date()
let data = try Data(contentsOf: url)
let raw = try JSONSerialization.jsonObject(with: data, options: [])
guard let cleaned = convert(raw) else { fatalError("input is null") }
let plist = try PropertyListSerialization.data(fromPropertyList: cleaned, format: .binary, options: 0)
try plist.write(to: outURL)
let elapsed = Date().timeIntervalSince(start)

let mbIn = Double(data.count) / 1024.0 / 1024.0
let mbOut = Double(plist.count) / 1024.0 / 1024.0
print(String(format: "json:  %.1f MB", mbIn))
print(String(format: "plist: %.1f MB", mbOut))
print(String(format: "wrote %@ in %.2fs", output, elapsed))
