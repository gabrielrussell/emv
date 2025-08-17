#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <error.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define ERROR_BUFFER_SIZE 4096

typedef struct {
  char *name;
} file_entry;

typedef struct {
  char *old_name;
  char *new_name;
} rename_entry;

static int compare_file_entry(const void *a, const void *b) {
  return strcmp(((file_entry *)a)->name, ((file_entry *)b)->name);
}

void free_file_entries(file_entry *files, int count) {
  for (int i = 0; i < count; i++) {
    free(files[i].name);
  }
  free(files);
}

void free_rename_entries(rename_entry *renames, int count) {
  for (int i = 0; i < count; i++) {
    free(renames[i].old_name);
    free(renames[i].new_name);
  }
  free(renames);
}

char *read_directory(char *error_buffer, const char *path, file_entry **files, int *count) {
  DIR *dir = NULL;
  struct dirent *entry;
  int capacity = 16;
  char *error_string = NULL;

  *count = 0;
  *files = NULL;

  *files = malloc(capacity * sizeof(file_entry));
  if (!*files) {
    error_string = "failed to allocate memory for file list";
    goto cleanup;
  }

  dir = opendir(path);
  if (!dir) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to open directory %s: %s", path, strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

  while (errno = 0, (entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] != '.' && strchr(entry->d_name, '\n') == NULL) {
      if (*count >= capacity) {
        capacity *= 2;
        file_entry *new_files = realloc(*files, capacity * sizeof(file_entry));
        if (!new_files) {
          error_string = "failed to reallocate memory for file list";
          goto cleanup;
        }
        *files = new_files;
      }
      (*files)[*count].name = strdup(entry->d_name);
      if (!(*files)[*count].name) {
        error_string = "failed to allocate memory for filename";
        goto cleanup;
      }
      (*count)++;
    }
  }

  if (errno != 0) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to read directory %s: %s", path, strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

  qsort(*files, *count, sizeof(file_entry), compare_file_entry);

cleanup:
  if (dir) {
    closedir(dir);
  }
  if (error_string && *files) {
    for (int i = 0; i < *count; i++) {
      free((*files)[i].name);
    }
    free(*files);
    *files = NULL;
    *count = 0;
  }
  return error_string;
}

char *create_temp_file(char *error_buffer, file_entry *files, int count, char **temp_path) {
  int fd = -1;
  FILE *fp = NULL;
  char *error_string = NULL;

  *temp_path = strdup("/tmp/emv_XXXXXX");
  if (!*temp_path) {
    error_string = "failed to allocate memory for temp path";
    goto cleanup;
  }
  
  fd = mkstemp(*temp_path);
  if (fd == -1) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to create temporary file %s: %s", *temp_path, strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

  fp = fdopen(fd, "w");
  if (!fp) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to open temporary file %s for writing: %s", *temp_path, strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

  for (int i = 0; i < count; i++) {
    fprintf(fp, "%s\n", files[i].name);
  }

cleanup:
  if (fp) {
    fclose(fp);
  } else if (fd != -1) {
    close(fd);
  }
  
  if (error_string && *temp_path) {
    free(*temp_path);
    *temp_path = NULL;
  }
  
  return error_string;
}

char *invoke_editor(char *error_buffer, const char *temp_path) {
  char *editor = getenv("EDITOR");
  pid_t pid;
  int status;
  char *error_string = NULL;

  if (!editor || strlen(editor) == 0) {
    error_string = "no EDITOR environment variable set";
    goto cleanup;
  }

  pid = fork();
  if (pid == -1) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to fork process for editor: %s", strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

  if (pid == 0) {
    execlp(editor, editor, temp_path, NULL);
    exit(1);
  }

  if (waitpid(pid, &status, 0) == -1) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to wait for editor process: %s", strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }
  
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    if (WIFEXITED(status)) {
      snprintf(error_buffer, ERROR_BUFFER_SIZE, "editor exited with status %d", WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
      snprintf(error_buffer, ERROR_BUFFER_SIZE, "editor terminated by signal %d", WTERMSIG(status));
    } else {
      snprintf(error_buffer, ERROR_BUFFER_SIZE, "editor exited abnormally");
    }
    error_string = error_buffer;
    goto cleanup;
  }

cleanup:
  return error_string;
}

char *read_edited_files(char *error_buffer, const char *temp_path, file_entry **new_files,
                        int *count) {
  FILE *fp = NULL;
  char *line = NULL;
  size_t line_len = 0;
  ssize_t read;
  int capacity = 16;
  char *error_string = NULL;

  *count = 0;
  *new_files = NULL;

  *new_files = malloc(capacity * sizeof(file_entry));
  if (!*new_files) {
    error_string = "failed to allocate memory for edited file list";
    goto cleanup;
  }

  fp = fopen(temp_path, "r");
  if (!fp) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to reopen temporary file %s for reading: %s", temp_path, strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

  while ((read = getline(&line, &line_len, fp)) != -1) {
    if (read > 0 && line[read - 1] == '\n') {
      line[read - 1] = '\0';
      read--;
    }
    if (read > 0) {
      if (*count >= capacity) {
        capacity *= 2;
        file_entry *new_entries =
            realloc(*new_files, capacity * sizeof(file_entry));
        if (!new_entries) {
          error_string = "failed to reallocate memory for edited file list";
          goto cleanup;
        }
        *new_files = new_entries;
      }
      (*new_files)[*count].name = strdup(line);
      if (!(*new_files)[*count].name) {
        error_string = "failed to allocate memory for edited filename";
        goto cleanup;
      }
      (*count)++;
    }
  }

  if (ferror(fp)) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to read from temporary file %s: %s", temp_path, strerror(errno));
    error_string = error_buffer;
    goto cleanup;
  }

cleanup:
  if (fp) {
    fclose(fp);
  }
  if (line) {
    free(line);
  }
  if (error_string && *new_files) {
    for (int i = 0; i < *count; i++) {
      free((*new_files)[i].name);
    }
    free(*new_files);
    *new_files = NULL;
    *count = 0;
  }
  return error_string;
}

char *analyze_renames(char *error_buffer __attribute__((unused)), file_entry *old_files, file_entry *new_files, int count,
                      rename_entry **renames, int *rename_count, int *tricky) {
  int *orig_count = calloc(count, sizeof(int));
  int *dest_count = calloc(count, sizeof(int));
  int *unchanged = calloc(count, sizeof(int));
  int capacity = count;
  char *error_string = NULL;

  *renames = malloc(capacity * sizeof(rename_entry));
  if (!orig_count || !dest_count || !unchanged || !*renames) {
    error_string = "failed to allocate memory for rename analysis";
    goto cleanup;
  }

  *rename_count = 0;
  *tricky = 0;

  for (int i = 0; i < count; i++) {
    if (strcmp(old_files[i].name, new_files[i].name) != 0) {
      (*renames)[*rename_count].old_name = strdup(old_files[i].name);
      (*renames)[*rename_count].new_name = strdup(new_files[i].name);
      if (!(*renames)[*rename_count].old_name ||
          !(*renames)[*rename_count].new_name) {
        error_string = "failed to allocate memory for rename entry";
        goto cleanup;
      }
      (*rename_count)++;

      orig_count[i]++;
      for (int j = 0; j < count; j++) {
        if (strcmp(new_files[i].name, old_files[j].name) == 0) {
          dest_count[j]++;
        }
      }
    } else {
      unchanged[i] = 1;
    }
  }

  if (!error_string) {
    // Check for duplicate new names
    for (int i = 0; i < *rename_count && !error_string; i++) {
      for (int j = i + 1; j < *rename_count; j++) {
        if (strcmp((*renames)[i].new_name, (*renames)[j].new_name) == 0) {
          error_string = "multiple files would be renamed to the same name";
          goto cleanup;
        }
      }
    }

    // Check for overwriting unchanged files and detect tricky renames
    for (int i = 0; i < count && !error_string; i++) {
      for (int j = 0; j < *rename_count && !error_string; j++) {
        if (strcmp((*renames)[j].new_name, old_files[i].name) == 0 &&
            unchanged[i]) {
          error_string = "rename would overwrite an existing unchanged file";
          break;
        }

        if (strcmp((*renames)[j].new_name, old_files[i].name) == 0 &&
            orig_count[i]) {
          *tricky = 1;
        }
      }
    }
  }

cleanup:
  if (error_string && *renames) {
    free_rename_entries(*renames, *rename_count);
    *renames = NULL;
  }
  free(orig_count);
  free(dest_count);
  free(unchanged);
  return error_string;
}

char *perform_renames(char *error_buffer, rename_entry *renames, int rename_count, int tricky) {
  char temp_dir[] = "./emv_temp_XXXXXX";
  char *error_string = NULL;
  int temp_dir_created = 0;

  if (tricky) {
    if (mkdtemp(temp_dir) == NULL) {
      snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to create temporary directory for tricky renames: %s", strerror(errno));
      error_string = error_buffer;
      goto cleanup;
    }
    temp_dir_created = 1;

    for (int i = 0; i < rename_count; i++) {
      char *temp_path;
      asprintf(&temp_path, "%s/%s", temp_dir, renames[i].old_name);
      if (!temp_path) {
        error_string = "failed to allocate memory for temporary path";
        goto cleanup;
      }

      if (rename(renames[i].old_name, temp_path) != 0) {
        snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to move %s to temporary location: %s",
                 renames[i].old_name, strerror(errno));
        error_string = error_buffer;
        free(temp_path);
        goto cleanup;
      }

      free(renames[i].old_name);
      renames[i].old_name = temp_path;
    }
  }

  for (int i = 0; i < rename_count; i++) {
    if (rename(renames[i].old_name, renames[i].new_name) != 0) {
      snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to rename %s to %s: %s",
               renames[i].old_name, renames[i].new_name, strerror(errno));
      error_string = error_buffer;
      goto cleanup;
    }
  }

cleanup:
  if (temp_dir_created) {
    if (rmdir(temp_dir) != 0) {
      if (!error_string) {
        snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to remove temporary directory %s: %s", temp_dir, strerror(errno));
        error_string = error_buffer;
      }
      // If error_string is already set, we don't want to overwrite the original error
    }
  }
  return error_string;
}

int main(int argc, char *argv[]) {
  file_entry *old_files = NULL;
  file_entry *new_files = NULL;
  rename_entry *renames = NULL;
  char *temp_path = NULL;
  char *error_string = NULL;
  char error_buffer[ERROR_BUFFER_SIZE];
  int old_count = 0, new_count = 0, rename_count = 0, tricky = 0;
  int temp_file_created = 0;

  if (argc > 1) {
    if (chdir(argv[1]) != 0) {
      snprintf(error_buffer, ERROR_BUFFER_SIZE, "failed to change to directory %s: %s", argv[1],
               strerror(errno));
      error_string = error_buffer;
      goto cleanup;
    }
  }

  error_string = read_directory(error_buffer, ".", &old_files, &old_count);
  if (error_string) {
    goto cleanup;
  }

  error_string = create_temp_file(error_buffer, old_files, old_count, &temp_path);
  if (error_string) {
    goto cleanup;
  }
  temp_file_created = 1;

  error_string = invoke_editor(error_buffer, temp_path);
  if (error_string)
    goto cleanup;

  error_string = read_edited_files(error_buffer, temp_path, &new_files, &new_count);
  if (error_string)
    goto cleanup;

  if (old_count != new_count) {
    snprintf(error_buffer, ERROR_BUFFER_SIZE,
             "file count changed: had %d files, now have %d files", old_count,
             new_count);
    error_string = error_buffer;
    goto cleanup;
  }

  error_string = analyze_renames(error_buffer, old_files, new_files, old_count, &renames,
                                 &rename_count, &tricky);
  if (error_string)
    goto cleanup;

  error_string = perform_renames(error_buffer, renames, rename_count, tricky);
  if (error_string)
    goto cleanup;

cleanup:
  if (temp_file_created && temp_path) {
    unlink(temp_path);
    free(temp_path);
  }
  if (old_files) {
    free_file_entries(old_files, old_count);
  }
  if (new_files) {
    free_file_entries(new_files, new_count);
  }
  if (renames) {
    free_rename_entries(renames, rename_count);
  }
  if (error_string) {
    error(1,0, "%s\n", error_string);
  }
  return 0;
}
