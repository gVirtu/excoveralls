defmodule ExCoveralls.LocalTest do
  use ExUnit.Case
  import Mock
  import ExUnit.CaptureIO
  alias ExCoveralls.Local

  @content     "defmodule Test do\n  def test do\n  end\nend\n"
  @counts      [0, 1, nil, nil]
  @source_info [%{name: "test/fixtures/test.ex",
                 source: @content,
                 coverage: @counts
               }]

  @invalid_counts [0, 1, nil, "invalid"]
  @invalid_source_info [%{name: "test/fixtures/test.ex",
                 source: @content,
                 coverage: @invalid_counts
               }]

  @empty_counts [nil, nil, nil, nil]
  @empty_source_info [%{name: "test/fixtures/test.ex",
                 source: @content,
                 coverage: @empty_counts
               }]

  @stats_result "" <>
      "----------------\n" <>
      "COV    FILE                                        LINES RELEVANT   MISSED\n" <>
      " 50.0% test/fixtures/test.ex                           4        2        1\n"  <>
      "[TOTAL]  50.0%\n" <>
      "----------------\n"

  @stats_result_with_uncovered_report "" <>
      "----------------\n" <>
      "COV    FILE                                        LINES RELEVANT   MISSED\n" <>
      " 50.0% test/fixtures/test.ex                           4        2        1\n"  <>
      "[TOTAL]  50.0%\n" <>
      "----------------\n" <>
      "#{IO.ANSI.yellow}UNCOVERED FILES\n" <>
      " 50.0% test/fixtures/test.ex                    L1#{IO.ANSI.reset}\n"

  @stats_no_files_results "Test Coverage [TOTAL]  50.0%\n"

  @source_result "" <>
      "\n\e[33m--------test/fixtures/test.ex--------\e[m\n" <>
      "\e[31mdefmodule Test do\e[m\n\e[32m  def test do\e[m\n" <>
      "  end\n" <>
      "end"

  test "display source information" do
    assert(Local.source(@source_info) =~ @source_result)
  end

  test "display source information with empty filter" do
    assert(Local.source(@source_info, []) =~ @source_result)
  end

  test "display source information with pattern filter" do
    assert(Local.source(@source_info, ["test.ex"]) =~ @source_result)
  end

  test "display stats information" do
    assert capture_io(fn ->
      Local.execute(@source_info)
    end) =~ @stats_result
  end

  test "display stats information with detail option" do
    assert capture_io(fn ->
      Local.execute(@source_info, [detail: true])
    end) =~ @stats_result <> @source_result <> "\n"
  end

  test_with_mock "display stats information with uncovered report",
    ExCoveralls.Settings, [
      get_coverage_options: fn -> %{"report_uncovered" => true} end,
      get_print_summary: fn -> true end,
      get_print_files: fn -> true end,
      get_file_col_width: fn -> 40 end
    ] do
    assert capture_io(fn ->
      Local.execute(@source_info)
    end) =~ @stats_result_with_uncovered_report
  end

  test "display stats information fails with invalid data" do
    assert_raise RuntimeError, fn ->
      Local.coverage(@invalid_source_info)
    end
  end

  test "Empty (no relevant lines) file is calculated as 0.0%" do
    assert String.contains?(Local.coverage(@empty_source_info), "[TOTAL] 100.0%")
  end

  test_with_mock "Empty (no relevant lines) file with treat_no_relevant_lines_as_covered=true option is calculated as 100.0%",
    ExCoveralls.Settings, [
      get_coverage_options: fn -> %{"treat_no_relevant_lines_as_covered" => true} end,
      get_file_col_width: fn -> 40 end,
      get_print_files: fn -> true end
    ] do
    assert String.contains?(Local.coverage(@empty_source_info), "[TOTAL] 100.0%")
  end

  test_with_mock "Empty (no relevant lines) file with treat_no_relevant_lines_as_covered=false option is calculated as 0.0%",
      ExCoveralls.Settings, [
        get_coverage_options: fn -> %{"treat_no_relevant_lines_as_covered" => false} end,
        get_file_col_width: fn -> 40 end,
        get_print_files: fn -> true end
      ] do
    assert String.contains?(Local.coverage(@empty_source_info), "[TOTAL]   0.0%")
  end

  test_with_mock "Exit status code is 1 when actual coverage does not reach the minimum",

      ExCoveralls.Settings, [
        get_coverage_options: fn -> %{"minimum_coverage" => 100} end,
        get_file_col_width: fn -> 40 end,
        get_print_summary: fn -> true end,
        get_print_files: fn -> true end
      ] do
    output = capture_io(fn ->
      assert catch_exit(Local.execute(@source_info)) == {:shutdown, 1}
    end)
    assert String.contains?(output, "FAILED: Expected minimum coverage of 100%, got 50%.")
  end

  test_with_mock "Exit status code is 0 when actual coverage reaches the minimum",
      ExCoveralls.Settings, [
        get_coverage_options: fn -> %{"minimum_coverage" => 49.9} end,
        get_file_col_width: fn -> 40 end,
        get_print_summary: fn -> true end,
        get_print_files: fn -> true end
      ] do
    assert capture_io(fn ->
      Local.execute(@source_info)
    end) =~ @stats_result
  end

  test_with_mock "No output if print_summary is false",
      ExCoveralls.Settings, [
        get_coverage_options: fn -> %{"minimum_coverage" => 49.9} end,
        get_file_col_width: fn -> 40 end,
        get_print_summary: fn -> true end,
        get_print_files: fn -> true end
      ] do
    assert capture_io(fn ->
      Local.execute(@source_info)
    end) =~ ""
  end

  test_with_mock "Do not output table if print_files is false",
      ExCoveralls.Settings, [
        get_coverage_options: fn -> %{"minimum_coverage" => 49.9} end,
        get_file_col_width: fn -> 40 end,
        get_print_summary: fn -> true end,
        get_print_files: fn -> false end
      ] do
    assert capture_io(fn ->
      Local.execute(@source_info)
    end) =~ @stats_no_files_results
  end
end
