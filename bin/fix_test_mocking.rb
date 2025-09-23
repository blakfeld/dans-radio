#!/usr/bin/env ruby

# Script to convert RSpec-style mocking to Mocha-style mocking in test files

require 'fileutils'

def fix_mocking_in_file(filepath)
  return unless File.exist?(filepath)

  content = File.read(filepath)
  original_content = content.dup

  # Replace expect(...).to receive with expects
  content.gsub!(/expect\(([^)]+)\)\.to receive\(([^)]+)\)\.with\(([^)]+)\)\.and_return\(([^)]+)\)/) do
    "#{$1}.expects(#{$2}).with(#{$3}).returns(#{$4})"
  end

  content.gsub!(/expect\(([^)]+)\)\.to receive\(([^)]+)\)\.and_return\(([^)]+)\)/) do
    "#{$1}.expects(#{$2}).returns(#{$3})"
  end

  content.gsub!(/expect\(([^)]+)\)\.to receive\(([^)]+)\)\.and_raise\(([^)]+)\)/) do
    "#{$1}.expects(#{$2}).raises(#{$3})"
  end

  content.gsub!(/expect\(([^)]+)\)\.to receive\(([^)]+)\)/) do
    "#{$1}.expects(#{$2})"
  end

  # Replace allow(...).to receive with stubs
  content.gsub!(/allow\(([^)]+)\)\.to receive\(([^)]+)\)\.and_return\(([^)]+)\)/) do
    "#{$1}.stubs(#{$2}).returns(#{$3})"
  end

  content.gsub!(/allow\(([^)]+)\)\.to receive\(([^)]+)\)/) do
    "#{$1}.stubs(#{$2})"
  end

  # Replace expect_any_instance_of
  content.gsub!(/expect_any_instance_of\(([^)]+)\)\.to receive\(([^)]+)\)\.and_return\(([^)]+)\)/) do
    "#{$1}.any_instance.expects(#{$2}).returns(#{$3})"
  end

  content.gsub!(/expect_any_instance_of\(([^)]+)\)\.to receive\(([^)]+)\)/) do
    "#{$1}.any_instance.expects(#{$2})"
  end

  content.gsub!(/allow_any_instance_of\(([^)]+)\)\.to receive\(([^)]+)\)\.and_return\(([^)]+)\)/) do
    "#{$1}.any_instance.stubs(#{$2}).returns(#{$3})"
  end

  # Replace expect(...).not_to receive
  content.gsub!(/expect\(([^)]+)\)\.not_to receive\(([^)]+)\)/) do
    "#{$1}.expects(#{$2}).never"
  end

  if content != original_content
    File.write(filepath, content)
    puts "Fixed #{filepath}"
    true
  else
    false
  end
end

# Fix all test files
test_files = Dir.glob('test/**/*_test.rb')
fixed_count = 0

test_files.each do |file|
  if fix_mocking_in_file(file)
    fixed_count += 1
  end
end

puts "Fixed #{fixed_count} files"

