#!/bin/bash

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
TOTAL=0

# Check if we should run under valgrind
if [[ "$VALGRIND" == "1" ]]; then
    VALGRIND_CMD="valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes --error-exitcode=1 --quiet"
    echo -e "${YELLOW}Running tests under valgrind...${NC}"
else
    VALGRIND_CMD=""
fi

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
    # Create test files
    touch "file1.txt" "file2.txt" "file3.txt"
    
    # Create a mock editor that renames files
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/file1\.txt/renamed1.txt/; s/file2\.txt/renamed2.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    # Run emv with mock editor
    EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv
    
    # Check results
    [[ -f "renamed1.txt" && -f "renamed2.txt" && -f "file3.txt" && ! -f "file1.txt" && ! -f "file2.txt" ]]
}

# Test: No changes (files stay the same)
test_no_changes() {
    touch "file1.txt" "file2.txt"
    
    # Mock editor that doesn't change anything
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
# Don't modify the file
exit 0
EOF
    chmod +x mock_editor.sh
    
    EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv
    
    # Files should remain the same
    [[ -f "file1.txt" && -f "file2.txt" ]]
}

# Test: Tricky renames (A->B, B->A swap)
test_swap_files() {
    touch "fileA.txt" "fileB.txt"
    
    # Mock editor that swaps filenames
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/fileA\.txt/temp_swap/; s/fileB\.txt/fileA.txt/; s/temp_swap/fileB.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv
    
    # Check that files were swapped correctly
    [[ -f "fileA.txt" && -f "fileB.txt" ]]
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
    ! EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv 2>/dev/null
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
    ! EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv 2>/dev/null
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
    ! EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv 2>/dev/null
}

# Test: Error - no EDITOR environment variable
test_no_editor_error() {
    touch "file1.txt"
    
    # Should fail when EDITOR is not set
    ! env -u EDITOR $VALGRIND_CMD ../emv 2>/dev/null
}

# Test: Long filenames (no truncation)
test_long_filenames() {
    # Create file with very long name
    long_name="very_long_filename_that_would_have_been_truncated_in_the_old_version_with_fixed_buffers_but_should_work_fine_now.txt"
    touch "$long_name"
    
    # Mock editor that renames to another long name
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/very_long_filename_that_would_have_been_truncated_in_the_old_version_with_fixed_buffers_but_should_work_fine_now\.txt/another_very_long_filename_that_tests_dynamic_allocation_and_should_not_be_truncated_at_all.txt/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv
    
    # Check that long filename rename worked
    [[ -f "another_very_long_filename_that_tests_dynamic_allocation_and_should_not_be_truncated_at_all.txt" && ! -f "$long_name" ]]
}

# Test: Many files (stress test)
test_many_files() {
    # Create 100 files
    for i in {1..100}; do
        touch "file_$i.txt"
    done
    
    # Mock editor that adds prefix to all files
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^/renamed_/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv
    
    # Check that all files were renamed
    local count=0
    for i in {1..100}; do
        if [[ -f "renamed_file_$i.txt" ]]; then
            count=$((count + 1))
        fi
    done
    
    [[ $count -eq 100 ]]
}

# Test: Special characters in filenames
test_special_characters() {
    # Create files with spaces and special characters
    touch "file with spaces.txt" "file-with-dashes.txt" "file_with_underscores.txt"
    
    # Mock editor that adds prefix
    cat > mock_editor.sh << 'EOF'
#!/bin/bash
sed 's/^/new_/' "$1" > tmp && mv tmp "$1"
EOF
    chmod +x mock_editor.sh
    
    EDITOR="./mock_editor.sh" $VALGRIND_CMD ../emv
    
    # Check results
    [[ -f "new_file with spaces.txt" && -f "new_file-with-dashes.txt" && -f "new_file_with_underscores.txt" ]]
}

# Main test execution
echo -e "${YELLOW}EMV Test Suite${NC}"
echo "================"

# Build the program first
echo "Building emv..."
make clean > /dev/null 2>&1
if ! make > /dev/null 2>&1; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

# Run all tests
run_test "Basic rename functionality" test_basic_rename
run_test "No changes (identity operation)" test_no_changes
run_test "Tricky renames (file swapping)" test_swap_files
run_test "File count mismatch error" test_file_count_error
run_test "Duplicate rename targets error" test_duplicate_rename_error
run_test "Overwrite existing file error" test_overwrite_error
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