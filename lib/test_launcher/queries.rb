module TestLauncher
  module Queries
    class CommandFinder
      def initialize(request)
        @request = request
      end

      def specified_name
        commandify(SpecifiedNameQuery)
      end

      def multi_search_term
        commandify(MultiTermQuery)
      end

      def by_path
        commandify(PathQuery)
      end

      def example_name
        commandify(ExampleNameQuery)
      end

      def from_full_regex
        commandify(FullRegexQuery)
      end

      def single_search_term
        commandify(SingleTermQuery)
      end

      def full_search
        commandify(SearchQuery)
      end

      def generic_search
        commandify(GenericQuery)
      end

      def line_number
        commandify(LineNumberQuery)
      end

      def request
        @request
      end

      def commandify(klass)
        klass.new(
          request,
          self
        ).command
      end
    end

    class BaseQuery
      attr_reader :shell, :searcher, :request
      def initialize(request, command_finder)
        @request = request
        @command_finder = command_finder
      end

      def command
        raise NotImplementedError
      end

      private

      def test_cases
        raise NotImplementedError
      end

      def runner
        request.runner
      end

      def shell
        request.shell
      end

      def searcher
        request.searcher
      end

      def one_file?
         file_count == 1
      end

      def file_count
        @file_count ||= test_cases.map {|tc| tc.file }.uniq.size
      end

      def most_recently_edited_test_case
        @most_recently_edited_test_case ||= test_cases.sort_by(&:mtime).last
      end

      def pluralize(count, singular)
        phrase = "#{count} #{singular}"
        if count == 1
          phrase
        else
          "#{phrase}s"
        end
      end

      def command_finder
        @command_finder
      end
    end

    class SpecifiedNameQuery < BaseQuery
      def command
        if test_cases.empty?
          shell.warn("Could not identify file: #{request.search_string}")
        elsif test_cases.size == 1
          shell.notify("Found 1 example in 1 file.")
          runner.single_example(test_cases.first)
        else
          shell.notify "Found #{pluralize(test_cases.size, "example")} in #{pluralize(file_count, "file")}."
          shell.notify "Running most recently edited. Run with '--all' to run all the tests."
          runner.single_example(most_recently_edited_test_case)
        end
      end

      def test_cases
        @test_cases ||= potential_files.map {|file|
          request.test_case(
            file: file,
            example: request.example_name,
            request: request,
          )
        }
      end

      def potential_files
        @potential_files ||= searcher.test_files(request.search_string)
      end
    end

    class MultiTermQuery < BaseQuery
      def command
        return if test_cases.empty?

        shell.notify("Found #{pluralize(file_count, "file")}.")
        runner.multiple_files(test_cases)
      end

      def test_cases
        @test_cases ||= files.map { |file_path|
          request.test_case(
            file: file_path,
            request: request,
          )
        }
      end

      def files
        if found_files.any? {|files_array| files_array.empty? }
          if !found_files.all? {|files_array| files_array.empty? }
            shell.warn("It looks like you're searching for multiple files, but we couldn't identify them all.")
          end
          []
        else
          found_files.flatten.uniq
        end
      end

      def found_files
        @found_files ||= queries.map {|query|
          searcher.test_files(query)
        }
      end

      def queries
        @queries ||= request.search_string.split(" ")
      end
    end

    class PathQuery < BaseQuery
      def command
        return if test_cases.empty?

        if one_file?
          shell.notify "Found #{pluralize(file_count, "file")}."
          runner.single_file(test_cases.first)
        elsif request.run_all?
          shell.notify "Found #{pluralize(file_count, "file")}."
          runner.multiple_files(test_cases)
        else
          shell.notify "Found #{pluralize(file_count, "file")}."
          shell.notify "Running most recently edited. Run with '--all' to run all the tests."
          runner.single_file(most_recently_edited_test_case)
        end
      end

      def test_cases
        @test_cases ||= files_found_by_path.map { |file_path|
          request.test_case(file: file_path, request: request)
        }
      end

      def files_found_by_path
        @files_found_by_path ||= searcher.test_files(request.search_string)
      end
    end

    class ExampleNameQuery < BaseQuery
      def command
        return if test_cases.empty?

        if one_example?
          shell.notify("Found 1 example in 1 file.")
          runner.single_example(test_cases.first)
        elsif one_file?
          shell.notify("Found #{test_cases.size} examples in 1 file.")
          runner.multiple_examples_same_file(test_cases) # it will regex with the query
        elsif request.run_all?
          shell.notify "Found #{pluralize(test_cases.size, "example")} in #{pluralize(file_count, "file")}."
          runner.multiple_examples(test_cases)
        else
          shell.notify "Found #{pluralize(test_cases.size, "example")} in #{pluralize(file_count, "file")}."
          shell.notify "Running most recently edited. Run with '--all' to run all the tests."
          runner.single_example(most_recently_edited_test_case) # let it regex the query
        end
      end

      def test_cases
        @test_cases ||=
          examples_found_by_name.map { |grep_result|
            request.test_case(
              file: grep_result[:file],
              example: request.search_string,
              line_number: grep_result[:line_number],
              request: request
            )
          }
      end

      def examples_found_by_name
        @examples_found_by_name ||= searcher.examples(request.search_string)
      end

      def one_example?
        test_cases.size == 1
      end
    end

    class FullRegexQuery < BaseQuery
      def command
        return if test_cases.empty?

        if one_file?
          shell.notify "Found #{pluralize(file_count, "file")}."
          runner.single_file(test_cases.first)
        elsif request.run_all?
          shell.notify "Found #{pluralize(file_count, "file")}."
          runner.multiple_files(test_cases)
        else
          shell.notify "Found #{pluralize(file_count, "file")}."
          shell.notify "Running most recently edited. Run with '--all' to run all the tests."
          runner.single_file(most_recently_edited_test_case)
        end
      end

      def test_cases
        @test_cases ||=
          files_found_by_full_regex
            .uniq { |grep_result| grep_result[:file] }
            .map { |grep_result|
              request.test_case(
                file: grep_result[:file],
                request: request
              )
            }
      end

      def files_found_by_full_regex
        @files_found_by_full_regex ||= searcher.grep(request.search_string)
      end
    end

    class LineNumberQuery < BaseQuery
      LINE_SPLIT_REGEX = /\A(?<file>.*):(?<line_number>\d+)\Z/

      def command
        return unless search_results.any?

        if one_file?
          shell.notify "Found #{pluralize(file_count, "file")}."
          runner.by_line_number(test_cases.first)
        else
          shell.notify "Found #{pluralize(file_count, "file")}."
          shell.notify "Cannot run all tests with --all because test frameworks don't accept multiple file/lines combos."
          runner.by_line_number(most_recently_edited_test_case)
        end
      end

      def test_cases
        @test_cases ||= search_results.map {|sr|
          request.test_case(
            file: sr[:file],
            line_number: sr[:line_number],
            example: sr[:example_name],
            request: request
          )
        }
      end

      def search_results
        @search_results ||= begin
          match = request.search_string.match(LINE_SPLIT_REGEX)
          if match
            searcher.by_line(match[:file], match[:line_number].to_i)
          else
            []
          end
        end
      end
    end

    class SingleTermQuery < BaseQuery
      def command
        [
          :by_path,
          :example_name,
          :from_full_regex,
        ]
          .each { |command_type|
            command = command_finder.public_send(command_type)
            return command if command
          }
        nil
      end
    end

    class SearchQuery < BaseQuery
      def command
        {
          multi_search_term: request.search_string.include?(" "),
          line_number: request.search_string.include?(":"),
          single_search_term: true
        }.each {|command_type, valid|
          next unless valid

          command = command_finder.public_send(command_type)
          return command if command
        }
        nil
      end
    end

    class GenericQuery < BaseQuery
      def command
        if request.example_name
          command_finder.specified_name
        else
          command_finder.full_search
        end
      end
    end
  end
end
