# NAME

emv - rename multiple files in a directory in bulk via editing a file
listing in a text editor

# SYNOPSIS

**emv** \[**-v** \| **-vv**\] \[*directory*\]

# DESCRIPTION

**emv** (edit move) allows you to rename multiple files by editing their
names in a text editor. It creates a list of filenames, opens your
editor, then renames files to match your changes.

Handles file swapping (A→B, B→A) using temporary storage. Validates
renames before executing.

# USAGE

When run, **emv** will:

1.  Scan the current directory (or specified directory) for filesystem
    objects

2.  Create a temporary file listing all names (excluding hidden entries)

3.  Open the file in your text editor (\$EDITOR environment variable)

4.  After you save and exit the editor, analyze the changes

5.  If there are any rename loops, move all to-be-renamed files to a
    temp directory

6.  Perform the rename operations to match your edited list

# ABORTING CHANGES

To cancel: quit without saving, or delete all lines and save (empty file
does nothing).

# OPTIONS

**-v**

:   Verbose mode. Print a summary of completed renames to stderr.

**-vv**

:   Extra verbose mode. Narrated walkthrough of each rename operation,
    including staging to temporary directory for complex renames.

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

# EDITING THE FILE LIST

When your editor opens, you\'ll see a list of names, one per line:

    hawaiibeach.jpg
    hawaiisunset.jpg
    vacationnotes.txt

You can edit this list to rename the objects:

    Hawaii Beach.jpg
    Hawaii Sunset.jpg
    Vacation Notes.txt

When you save and exit, they will be renamed accordingly.

# RENAME RULES

**Entry count must remain the same**

:   You cannot add or remove lines from the list. The number of entries
    must remain constant.

**No duplicate names**

:   You cannot rename multiple entries to the same name.

**No slashes in names**

:   Renamed entries cannot contain \'/\' characters. emv operates on a
    single directory.

**No overwriting unchanged entries**

:   You cannot rename an entry to the name of an existing entry that you
    didn\'t also rename.

# ERROR CONDITIONS

**emv** will refuse to proceed and display an error message if:

-   The EDITOR environment variable is not set

-   The editor exits with a non-zero status

-   The number of lines in the edited file differs from the original

-   Multiple entries would be renamed to the same name

-   A renamed entry contains a \'/\' character

-   A rename would overwrite an existing unchanged entry

# WARNING

-   File system errors during rename operations may leave some files
    renamed and others not. No rollback mechanism.

# FILES

**/tmp/emv_XXXXXX**

:   Temporary file used for editing the name list

**./emv_temp_XXXXXX**

:   Temporary directory created when complex renames require
    intermediate storage

# NOTES

-   Silently ignores files starting with \'.\'

-   Silently ignores entries containing newline characters

-   Editing the order of files is a footgun. Deleting the first line and
    adding it to the end will give every file the name of the previous
    file in the list.

-   If you\'ve made edits and want to make sure that no renames happen,
    you can just delete all of the lines in the file. An empty file will
    always cause no renames to happen.

# SEE ALSO

**mv**(1), **rename**(1), **vidir**(1), **mmv**(1)

# BUGS

Report bugs at: https://github.com/gabrielrussell/emv/issues

# AUTHOR

Gabriel Russell

# COPYRIGHT

To the extent possible under law, the author has waived all copyright
and related rights to this work. See the LICENSE file or
https://creativecommons.org/publicdomain/zero/1.0/
