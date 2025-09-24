#!/usr/bin/env ruby

# Fix session parameter issues in controller tests

Dir.glob('test/controllers/**/*_test.rb').each do |file|
  content = File.read(file)

  # Fix get/post/put/delete calls with session as separate parameter
  content.gsub!(/get\s+(\S+),\s*session:\s*\{([^}]+)\}/) do
    "get #{$1}, params: {}, session: {#{$2}}"
  end

  content.gsub!(/post\s+(\S+),\s*params:\s*\{([^}]+)\},\s*session:\s*\{([^}]+)\}/) do
    "post #{$1}, params: {#{$2}}, session: {#{$3}}"
  end

  content.gsub!(/get\s+(\S+),\s*params:\s*\{([^}]+)\},\s*session:\s*\{([^}]+)\}/) do
    "get #{$1}, params: {#{$2}}, session: {#{$3}}"
  end

  File.write(file, content)
  puts "Fixed #{file}"
end

puts "Done!"
