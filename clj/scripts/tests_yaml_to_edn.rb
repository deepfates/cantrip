#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

def edn(value)
  case value
  when NilClass
    "nil"
  when TrueClass
    "true"
  when FalseClass
    "false"
  when Numeric
    value.to_s
  when String
    value.inspect
  when Array
    "[" + value.map { |v| edn(v) }.join(" ") + "]"
  when Hash
    "{" + value.map { |k, v| "#{edn_key(k)} #{edn(v)}" }.join(" ") + "}"
  else
    value.to_s.inspect
  end
end

def edn_key(key)
  str = key.to_s
  if str.match?(/\A[a-zA-Z][a-zA-Z0-9_\-]*\z/)
    ":" + str.tr("_", "-")
  else
    edn(str)
  end
end

path = File.expand_path("../tests.yaml", __dir__)
data = YAML.load_file(path)
puts edn(data)
