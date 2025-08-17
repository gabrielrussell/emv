# NAME

emv - rename multiple files in a directory all at once with a text
editor

# SYNOPSIS

**emv** \[*directory*\]

# DESCRIPTION

**emv** (edit move) is a utility that allows you to rename multiple
filesystem objects (files, directories, symbolic links, etc.) by editing
their names in your preferred text editor. It presents a list of names
in a temporary file, opens your editor to modify the list, and then
performs the necessary rename operations to match your edits.

The program tries to handle complex rename scenarios including file
swapping (A→B, B→A) by using temporary storage when necessary. It tries
to validate all rename operations before executing them to try to
prevent data loss.

# USAGE

When run, **emv** will:

1.  Scan the current directory (or specified directory) for filesystem
    objects

2.  Create a temporary file listing all names (excluding hidden entries)

3.  Open the file in your text editor (\$EDITOR environment variable)

4.  After you save and exit the editor, analyze the changes

5.  Perform the rename operations to match your edited list

# ARGUMENTS

*directory*

:   Optional directory to operate in. If not specified, operates in the
    current directory.

# ENVIRONMENT

**EDITOR**

:   The text editor to use for editing the file list. This environment
    variable must be set. Common values include \"vim\", \"emacs\",
    \"nano\", or \"code\".

# EXAMPLES

**emv**

:   Rename files and directories in the current directory

**emv /path/to/photos**

:   Rename files and directories in the /path/to/photos directory

**EDITOR=nano emv**

:   Use nano as the editor for this session

# EDITING THE FILE LIST

When your editor opens, you\'ll see a list of names, one per line:

    photo001.jpg
    photo002.jpg
    vacation.txt

You can edit this list to rename the objects:

    hawaii_beach.jpg
    hawaii_sunset.jpg
    vacation_notes.txt

When you save and exit, they will be renamed accordingly.

# RENAME RULES

**Entry count must remain the same**

:   You cannot add or remove lines from the list. The number of entries
    must remain constant.

**No duplicate names**

:   You cannot rename multiple entries to the same name.

**No overwriting unchanged entries**

:   You cannot rename an entry to the name of an existing entry that you
    didn\'t also rename.

**Complex renames are supported**

:   Entry swapping (A→B, B→A) and circular renames are automatically
    handled using temporary storage.

# ERROR CONDITIONS

**emv** will refuse to proceed and display an error message if:

-   The EDITOR environment variable is not set

-   The editor exits with a non-zero status

-   The number of lines in the edited file differs from the original

-   Multiple entries would be renamed to the same name

-   A rename would overwrite an existing unchanged entry

# WARNING

-   File system errors occur during rename operations will cause the
    program to leave the renames possibly half done without any plan for
    rollback or resume.

# EXIT STATUS

**0**

:   Success

**1**

:   Error occurred (invalid arguments, editor failure, rename conflicts,
    file system errors)

# FILES

**/tmp/emv_XXXXXX**

:   Temporary file used for editing the name list

**./emv_temp_XXXXXX**

:   Temporary directory created when complex renames require
    intermediate storage

# NOTES

-   Should work on all filesystem objects: files, directories, symbolic
    links, etc.

-   Hidden entries (those starting with \'.\') are ignored

-   Entries containing newline characters in their names are ignored

# SEE ALSO

**mv**(1), **rename**(1), **vidir**(1), **mmv**(1)

# BUGS

Report bugs at: https://github.com/gabrielrussell/emv/issues

# AUTHOR

Gabriel Russell

# COPYRIGHT

This software is provided as-is without warranty. See the source code
for license details.
