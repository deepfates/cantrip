#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

path = File.expand_path("../tests.yaml", __dir__)
tests = YAML.load_file(path)

unless tests.is_a?(Array)
  warn "Expected tests.yaml root to be a YAML sequence."
  exit 1
end

rule_counts = Hash.new(0)
tests.each do |row|
  next unless row.is_a?(Hash) && row["rule"].is_a?(String)

  prefix = row["rule"].split("-").first
  rule_counts[prefix] += 1
end

total = tests.length
skipped = tests.count { |row| row.is_a?(Hash) && row["skip"] == true }

puts "Conformance preflight OK"
puts "  tests: #{total}"
puts "  skipped: #{skipped}"
puts "  families:"
rule_counts.sort.each do |prefix, count|
  puts "    #{prefix}: #{count}"
end
