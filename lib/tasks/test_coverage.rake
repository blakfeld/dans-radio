namespace :test do
  desc "Run all tests with code coverage report"
  task :coverage do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    puts "=" * 80
    puts "Running Tests with Coverage Analysis"
    puts "=" * 80
    puts

    # Prepare test database
    Rake::Task["db:test:prepare"].invoke

    # Run all tests
    Rake::Task["test"].invoke

    puts
    puts "=" * 80
    puts "Coverage report generated at: coverage/index.html"
    puts "Open with: open coverage/index.html"
    puts "=" * 80
  end

  desc "Run model tests with coverage"
  task :models do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    system("rails test test/models")
  end

  desc "Run controller tests with coverage"
  task :controllers do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    system("rails test test/controllers")
  end

  desc "Run service tests with coverage"
  task :services do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    system("rails test test/services")
  end

  desc "Run job tests with coverage"
  task :jobs do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    system("rails test test/jobs")
  end

  desc "Run helper tests with coverage"
  task :helpers do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    system("rails test test/helpers")
  end

  desc "Generate test coverage summary"
  task :summary do
    ENV["COVERAGE"] = "true"
    ENV["RAILS_ENV"] = "test"

    puts "Generating test coverage summary..."

    # Run tests quietly to generate coverage
    system("rails test > /dev/null 2>&1")

    # Parse and display coverage summary
    coverage_file = "coverage/.last_run.json"
    if File.exist?(coverage_file)
      require "json"
      data = JSON.parse(File.read(coverage_file))

      puts
      puts "Test Coverage Summary:"
      puts "-" * 40

      data["result"]["covered_percent_group"].each do |group, percentage|
        status = case percentage
        when 90..100 then "✅"
        when 80..89 then "⚠️"
        else "❌"
        end
        printf "%s %-20s %6.2f%%\n", status, "#{group}:", percentage
      end

      puts "-" * 40
      total = data["result"]["covered_percent"]
      status = case total
      when 90..100 then "✅"
      when 80..89 then "⚠️"
      else "❌"
      end
      printf "%s %-20s %6.2f%%\n", status, "TOTAL:", total
      puts
    else
      puts "No coverage data found. Run 'rake test:coverage' first."
    end
  end
end

desc "Run all tests with coverage (alias for test:coverage)"
task coverage: "test:coverage"

