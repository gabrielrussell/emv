#!/bin/bash

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
TOTAL=0

# Check if we should run in verbose mode first
if [[ "$VERBOSE" == "1" || "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE_MODE=1
    echo -e "${YELLOW}Running tests in verbose mode...${NC}"
    #set -x  # Enable bash command tracing
else
    VERBOSE_MODE=0
fi

# Check if we should run under valgrind
if [[ "$VALGRIND" == "1" ]]; then
    if [[ "$VERBOSE_MODE" == "1" ]]; then
        VALGRIND_CMD="valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes --error-exitcode=1"
    else
        VALGRIND_CMD="valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes --error-exitcode=1 --quiet"
    fi
    echo -e "${YELLOW}Running tests under valgrind...${NC}"
else
    VALGRIND_CMD=""
fi

# Function to run commands with optional verbosity
run_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$VERBOSE_MODE" == "1" ]]; then
        echo -e "${YELLOW}Running:${NC} $description"
        echo -e "${YELLOW}Command:${NC} $cmd"
        echo -e "${YELLOW}Output:${NC}"
    fi
    
    # Run the command and capture both stdout and stderr
    if [[ "$VERBOSE_MODE" == "1" ]]; then
        eval "$cmd"
        local exit_code=$?
        echo -e "${YELLOW}Exit code:${NC} $exit_code"
        return $exit_code
    else
        eval "$cmd"
        return $?
    fi
}

# Function to print test results
print_result() {
    local test_name="$1"
    local result="$2"
    TOTAL=$((TOTAL + 1))
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        FAILED=$((FAILED + 1))
    fi
}

# Function to run a test
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    echo -e "\n${YELLOW}Running:${NC} $test_name"
    
    # Create clean test directory
    rm -rf test_tmp
    mkdir test_tmp
    cd test_tmp
    
    # Run the test
    if $test_func; then
        print_result "$test_name" "PASS"
    else
        print_result "$test_name" "FAIL"
    fi
    
    cd ..
    rm -rf test_tmp
}

# Test: Basic rename functionality
test_basic_rename() {
    # Create test files with unique content
    echo "content of file 1" > "file1.txt"
    echo "content of file 2" > "file2.txt"
    echo "content of file 3" > "file3.txt"
    
    # Create a mock editor that renames files
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/file1\.txt/renamed1.txt/; s/file2\.txt/renamed2.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    # Run emv with mock editor
    run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv with basic rename"
    
    # Check that files exist with correct names
    [[ -f "renamed1.txt" && -f "renamed2.txt" && -f "file3.txt" && ! -f "file1.txt" && ! -f "file2.txt" ]] || return 1
    
    # Check that content moved correctly with the filenames
    [[ "$(cat renamed1.txt)" == "content of file 1" ]] || return 1
    [[ "$(cat renamed2.txt)" == "content of file 2" ]] || return 1
    [[ "$(cat file3.txt)" == "content of file 3" ]] || return 1
}

# Test: No changes (files stay the same)
test_no_changes() {
    # Create files with content
    echo "unchanged content 1" > "file1.txt"
    echo "unchanged content 2" > "file2.txt"
    
    # Mock editor that doesn't change anything
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
# Don't modify the file
exit 0
EOF
    chmod +x mock_editor.sh
    
    run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv with no changes"
    
    # Files should remain the same
    [[ -f "file1.txt" && -f "file2.txt" ]] || return 1
    
    # Content should remain unchanged
    [[ "$(cat file1.txt)" == "unchanged content 1" ]] || return 1
    [[ "$(cat file2.txt)" == "unchanged content 2" ]] || return 1
}

# Test: Tricky renames (A->B, B->A swap)
test_swap_files() {
    # Create files with distinct content to verify correct swapping
    echo "This was originally fileA" > "fileA.txt"
    echo "This was originally fileB" > "fileB.txt"
    
    # Mock editor that swaps filenames
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/fileA\.txt/temp_swap/; s/fileB\.txt/fileA.txt/; s/temp_swap/fileB.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv with file swap"
    
    # Check that files exist with swapped names
    [[ -f "fileA.txt" && -f "fileB.txt" ]] || return 1
    
    # Most importantly: verify that content was swapped correctly
    # fileA.txt should now contain the original fileB content
    [[ "$(cat fileA.txt)" == "This was originally fileB" ]] || return 1
    # fileB.txt should now contain the original fileA content  
    [[ "$(cat fileB.txt)" == "This was originally fileA" ]] || return 1
}

# Test: Error - file count mismatch (line deletion)
test_file_count_error() {
    touch "file1.txt" "file2.txt"
    
    # Mock editor that deletes a line
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
head -n 1 "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    # Should fail with file count error
    ! run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv expecting file count error"
}

# Test: Error - duplicate rename targets
test_duplicate_rename_error() {
    touch "file1.txt" "file2.txt" "file3.txt"
    
    # Mock editor that creates duplicate names
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/file[12]\.txt/duplicate.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    # Should fail with non-unique renames error
    ! run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv expecting duplicate rename error"
}

# Test: Error - overwrite existing file
test_overwrite_error() {
    touch "file1.txt" "file2.txt" "existing.txt"
    
    # Mock editor that tries to rename file1 to existing.txt
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/file1\.txt/existing.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    # Should fail with overwrite error
    ! run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv expecting overwrite error"
}

# Test: Error - slash in destination name
test_slash_in_name_error() {
    touch "file1.txt" "file2.txt"

    # Mock editor that introduces a slash in a filename
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/file1\.txt/subdir\/file1.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh

    # Should fail with slash error
    ! run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv expecting slash in name error"
}

# Test: Error - no EDITOR environment variable
test_no_editor_error() {
    touch "file1.txt"
    
    # Should fail when EDITOR is not set
    ! run_cmd "env -u EDITOR $VALGRIND_CMD ../emv" "Running emv expecting no EDITOR error"
}

# Test: Long filenames (no truncation)
test_long_filenames() {
    # Create file with very long name and unique content
    long_name="very_long_filename_that_would_have_been_truncated_in_the_old_version_with_fixed_buffers_but_should_work_fine_now.txt"
    echo "content for very long filename test" > "$long_name"
    
    # Mock editor that renames to another long name
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/very_long_filename_that_would_have_been_truncated_in_the_old_version_with_fixed_buffers_but_should_work_fine_now\.txt/another_very_long_filename_that_tests_dynamic_allocation_and_should_not_be_truncated_at_all.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv with long filenames"
    
    # Check that long filename rename worked
    new_long_name="another_very_long_filename_that_tests_dynamic_allocation_and_should_not_be_truncated_at_all.txt"
    [[ -f "$new_long_name" && ! -f "$long_name" ]] || return 1
    
    # Verify content moved with the filename
    [[ "$(cat "$new_long_name")" == "content for very long filename test" ]] || return 1
}

# Test: Many files (stress test)
test_many_files() {
    # Create 100 files with unique content
    for i in {1..100}; do
        echo "content of file number $i" > "file_$i.txt"
    done
    
    # Mock editor that adds prefix to all files
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^/renamed_/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv with many files stress test"
    
    # Check that all files were renamed and content is correct
    local count=0
    for i in {1..100}; do
        if [[ -f "renamed_file_$i.txt" ]]; then
            # Verify content moved correctly
            if [[ "$(cat "renamed_file_$i.txt")" == "content of file number $i" ]]; then
                count=$((count + 1))
            fi
        fi
    done
    
    [[ $count -eq 100 ]]
}

# Test: Special characters in filenames
test_special_characters() {
    # Create files with spaces and special characters, each with unique content
    echo "content with spaces" > "file with spaces.txt"
    echo "content with dashes" > "file-with-dashes.txt"
    echo "content with underscores" > "file_with_underscores.txt"
    
    # Mock editor that adds prefix
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^/new_/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv with special characters"
    
    # Check that files exist with new names
    [[ -f "new_file with spaces.txt" && -f "new_file-with-dashes.txt" && -f "new_file_with_underscores.txt" ]] || return 1
    
    # Verify content moved correctly with special character filenames
    [[ "$(cat "new_file with spaces.txt")" == "content with spaces" ]] || return 1
    [[ "$(cat "new_file-with-dashes.txt")" == "content with dashes" ]] || return 1
    [[ "$(cat "new_file_with_underscores.txt")" == "content with underscores" ]] || return 1
}

# Test: Partial rename failure produces a report
test_partial_rename_report() {
    # Create three files: aaa, bbb, ccc (sorted order matters)
    echo "content a" > "aaa"
    echo "content b" > "bbb"
    echo "content c" > "ccc"

    # Mock editor that renames all three files AND creates a blocking
    # directory at bbb's destination. The directory isn't in the original
    # listing, so it passes validation, but rename() fails with EISDIR.
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/new_aaa/; s/^bbb$/new_bbb/; s/^ccc$/new_ccc/' "$1" > tmp && mv tmp "$1"
mkdir new_bbb
EOF
    chmod +x mock_editor.sh

    # Capture stderr
    local stderr_output
    stderr_output=$(EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv 2>&1 1>/dev/null)

    # Should have failed
    [[ $? -ne 0 ]] || return 1

    # Report should show aaa was renamed, bbb failed, ccc is pending
    echo "$stderr_output" | grep -q "renamed:" || return 1
    echo "$stderr_output" | grep -q "FAILED:" || return 1
    echo "$stderr_output" | grep -q "pending:" || return 1

    # aaa should have been renamed (it was before the failure)
    [[ -f "new_aaa" ]] || return 1
    [[ "$(cat new_aaa)" == "content a" ]] || return 1

    # bbb should still exist (rename failed)
    [[ -f "bbb" ]] || return 1

    # ccc should still exist (not attempted)
    [[ -f "ccc" ]] || return 1
}

# Test: Tricky rename pass-2 failure report
test_tricky_rename_failure() {
    # Create files that trigger a tricky rename (swap aaa<->bbb, plus rename ccc)
    echo "content a" > "aaa"
    echo "content b" > "bbb"
    echo "content c" > "ccc"

    # Mock editor: swap aaa<->bbb, rename ccc->ddd.
    # Also creates a directory at "ddd" to block pass-2 rename of ccc->ddd.
    # The directory isn't in the original listing (created after the scan),
    # so it passes validation, but rename() fails with EISDIR in pass 2.
    cat > .mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/__SWAP__/; s/^bbb$/aaa/; s/^__SWAP__$/bbb/; s/^ccc$/ddd/' "$1" > tmp && mv tmp "$1"
mkdir ddd
EOF
    chmod +x .mock_editor.sh

    # Capture stderr
    local stderr_output
    stderr_output=$(EDITOR="./.mock_editor.sh" $VALGRIND_CMD ../emv 2>&1 1>/dev/null)

    # Should have failed
    [[ $? -ne 0 ]] || return 1

    # Report should show the swap succeeded but ccc->ddd failed
    echo "$stderr_output" | grep -q "FAILED:" || return 1
    echo "$stderr_output" | grep -q "rename report:" || return 1

    # The swap should have completed (aaa and bbb swapped)
    [[ -f "aaa" && "$(cat aaa)" == "content b" ]] || return 1
    [[ -f "bbb" && "$(cat bbb)" == "content a" ]] || return 1

    # The temp directory should still exist with ccc stranded in it
    local temp_dir
    temp_dir=$(ls -d emv_temp_* 2>/dev/null)
    [[ -n "$temp_dir" && -d "$temp_dir" ]] || return 1
    [[ -f "$temp_dir/ccc" && "$(cat "$temp_dir/ccc")" == "content c" ]] || return 1
}

# Test: Editor exits with non-zero status
test_editor_exit_failure() {
    touch "file1.txt" "file2.txt"

    cat > mock_editor.sh << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x mock_editor.sh

    ! run_cmd "EDITOR=\"./mock_editor.sh\" $VALGRIND_CMD ../emv" "Running emv expecting editor failure"
}

# Test: Bad command-line flag
test_bad_flag() {
    touch "file1.txt"

    local stderr_output
    stderr_output=$($VALGRIND_CMD ../emv -z 2>&1 1>/dev/null)
    [[ $? -ne 0 ]] || return 1
    echo "$stderr_output" | grep -q "usage:" || return 1
}

# Test: Directory argument
test_directory_argument() {
    mkdir subdir
    echo "content a" > subdir/aaa
    echo "content b" > subdir/bbb

    # Editor path must be absolute since emv chdir's to subdir
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/renamed_a/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    local editor_path
    editor_path=$(pwd)/mock_editor.sh

    run_cmd "EDITOR=\"$editor_path\" $VALGRIND_CMD ../emv subdir" "Running emv with directory argument"

    [[ -f "subdir/renamed_a" && ! -f "subdir/aaa" ]] || return 1
    [[ "$(cat subdir/renamed_a)" == "content a" ]] || return 1
    [[ "$(cat subdir/bbb)" == "content b" ]] || return 1
}

# Test: Verbose flag (-v) output
test_verbose_output() {
    echo "content a" > "aaa"
    echo "content b" > "bbb"

    cat > .mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/ccc/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x .mock_editor.sh

    local stderr_output
    stderr_output=$(EDITOR="./.mock_editor.sh" $VALGRIND_CMD ../emv -v 2>&1 1>/dev/null)
    [[ $? -eq 0 ]] || return 1
    echo "$stderr_output" | grep -q "aaa -> ccc" || return 1
}

# Test: Extra verbose flag (-vv) output with tricky rename
test_extra_verbose_output() {
    echo "content a" > "aaa"
    echo "content b" > "bbb"

    cat > .mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/__SWAP__/; s/^bbb$/aaa/; s/^__SWAP__$/bbb/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x .mock_editor.sh

    local stderr_output
    stderr_output=$(EDITOR="./.mock_editor.sh" $VALGRIND_CMD ../emv -vv 2>&1 1>/dev/null)
    [[ $? -eq 0 ]] || return 1
    echo "$stderr_output" | grep -q "creating temp directory" || return 1
    echo "$stderr_output" | grep -q "staging" || return 1
    echo "$stderr_output" | grep -q "renaming" || return 1
    echo "$stderr_output" | grep -q "removing temp directory" || return 1
    echo "$stderr_output" | grep -q "aaa -> bbb" || return 1
}

# Test: Tricky rename pass-1 (staging) failure
test_tricky_rename_staging_failure() {
    echo "content a" > "aaa"
    echo "content b" > "bbb"

    # Mock editor: swap aaa<->bbb, and delete aaa from the filesystem.
    # emv tries to stage aaa first (alphabetical order) and gets ENOENT.
    cat > .mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/__SWAP__/; s/^bbb$/aaa/; s/^__SWAP__$/bbb/' "$1" > tmp && mv tmp "$1"
rm aaa
EOF
    chmod +x .mock_editor.sh

    local stderr_output
    stderr_output=$(EDITOR="./.mock_editor.sh" $VALGRIND_CMD ../emv 2>&1 1>/dev/null)
    [[ $? -ne 0 ]] || return 1
    echo "$stderr_output" | grep -q "FAILED:" || return 1
    echo "$stderr_output" | grep -q "rename report:" || return 1

    # bbb should still be at its original location (not staged)
    [[ -f "bbb" && "$(cat bbb)" == "content b" ]] || return 1
}

# Test: File created while editor is open doesn't get silently overwritten
test_noreplace() {
    echo "content a" > "aaa"
    echo "content b" > "bbb"

    # Mock editor renames aaa->ccc, but also creates ccc on disk.
    # renameat2 RENAME_NOREPLACE should prevent the overwrite.
    cat > .mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^aaa$/ccc/' "$1" > tmp && mv tmp "$1"
echo "new content" > ccc
EOF
    chmod +x .mock_editor.sh

    local stderr_output
    stderr_output=$(EDITOR="./.mock_editor.sh" $VALGRIND_CMD ../emv 2>&1 1>/dev/null)
    [[ $? -ne 0 ]] || return 1

    # The pre-existing ccc should not have been overwritten
    [[ -f "ccc" && "$(cat ccc)" == "new content" ]] || return 1

    # aaa should still exist (rename failed)
    [[ -f "aaa" && "$(cat aaa)" == "content a" ]] || return 1
}

# Main test execution
echo -e "${YELLOW}EMV Test Suite${NC}"
echo "================"

# Run all tests
run_test "Basic rename functionality" test_basic_rename
run_test "No changes (identity operation)" test_no_changes
run_test "Tricky renames (file swapping)" test_swap_files
run_test "File count mismatch error" test_file_count_error
run_test "Duplicate rename targets error" test_duplicate_rename_error
run_test "Overwrite existing file error" test_overwrite_error
run_test "Slash in destination name error" test_slash_in_name_error
run_test "Partial rename failure report" test_partial_rename_report
run_test "Tricky rename pass-2 failure" test_tricky_rename_failure
run_test "Editor exits with failure" test_editor_exit_failure
run_test "Bad command-line flag" test_bad_flag
run_test "Directory argument" test_directory_argument
run_test "Verbose flag output" test_verbose_output
run_test "Extra verbose output (tricky)" test_extra_verbose_output
run_test "Tricky rename staging failure" test_tricky_rename_staging_failure
run_test "No-clobber rename (RENAME_NOREPLACE)" test_noreplace
run_test "No EDITOR environment error" test_no_editor_error
run_test "Long filenames support" test_long_filenames
run_test "Many files stress test" test_many_files
run_test "Special characters in filenames" test_special_characters

# Print summary
echo
echo "================"
echo -e "Tests completed: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC} out of $TOTAL total"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
