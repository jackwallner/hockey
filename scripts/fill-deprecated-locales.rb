#!/usr/bin/env ruby
# Fill in release_notes and promotional_text on deprecated locales that ASC still requires.
# These locales exist in ASC version metadata but can't be "activated" via the modern API.

require "spaceship"
require "json"

# Get the release notes + promo text from en-US (already written to disk by fastlane)
EN_LOCALE = "en-US"
RELEASE_NOTES = File.read("fastlane/metadata/#{EN_LOCALE}/release_notes.txt").strip
PROMO_TEXT = File.read("fastlane/metadata/#{EN_LOCALE}/promotional_text.txt").strip

DEPRECATED_LOCALES = %w[
  bn-BD gu-IN kn-IN ml-IN mr-IN or-IN pa-IN sl-SI ta-IN te-IN ur-PK
]

key_id = ENV["ASC_API_KEY_ID"]
issuer_id = ENV["ASC_ISSUER_ID"]
key_path = ENV["ASC_KEY_PATH"]

Spaceship::ConnectAPI::Token.create(
  key_id: key_id,
  issuer_id: issuer_id,
  filepath: key_path
)

app = Spaceship::ConnectAPI::App.find("com.jackwallner.baseball")
version = app.get_edit_app_store_version

if version.nil?
  puts "ERROR: No editable version found (not in Prepare for Submission)"
  exit 1
end

puts "Version: #{version.version_string} (#{version.id})"

version.get_app_store_version_localizations.each do |loc|
  locale = loc.locale
  if DEPRECATED_LOCALES.include?(locale)
    puts "Filling #{locale}..."

    loc.update(
      what_s_new: RELEASE_NOTES,
      promotional_text: PROMO_TEXT
    )

    puts "  Done: #{locale}"
  end
end

puts "All deprecated locales filled."
