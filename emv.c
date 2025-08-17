#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <libgen.h>
#include <error.h>

typedef struct {
    char *name;
} file_entry;

typedef struct {
    char *old_name;
    char *new_name;
} rename_entry;

static int compare_strings(const void *a, const void *b) {
    return strcmp(((file_entry*)a)->name, ((file_entry*)b)->name);
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

char *read_directory(const char *path, file_entry **files, int *count) {
    DIR *dir;
    struct dirent *entry;
    int capacity = 16;
    *count = 0;
    
    *files = malloc(capacity * sizeof(file_entry));
    if (!*files) {
        return strdup("failed to allocate memory for file list");
    }
    
    dir = opendir(path);
    if (!dir) {
        free(*files);
        *files = NULL;
        return strdup("failed to open directory");
    }
    
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] != '.' && strchr(entry->d_name, '\n') == NULL) {
            if (*count >= capacity) {
                capacity *= 2;
                file_entry *new_files = realloc(*files, capacity * sizeof(file_entry));
                if (!new_files) {
                    closedir(dir);
                    for (int i = 0; i < *count; i++) {
                        free((*files)[i].name);
                    }
                    free(*files);
                    *files = NULL;
                    return strdup("failed to reallocate memory for file list");
                }
                *files = new_files;
            }
            (*files)[*count].name = strdup(entry->d_name);
            if (!(*files)[*count].name) {
                closedir(dir);
                for (int i = 0; i < *count; i++) {
                    free((*files)[i].name);
                }
                free(*files);
                *files = NULL;
                return strdup("failed to allocate memory for filename");
            }
            (*count)++;
        }
    }
    
    closedir(dir);
    qsort(*files, *count, sizeof(file_entry), compare_strings);
    return NULL;
}

char *create_temp_file(file_entry *files, int count, char *temp_path) {
    int fd;
    FILE *fp;
    
    strcpy(temp_path, "/tmp/emv_XXXXXX");
    fd = mkstemp(temp_path);
    if (fd == -1) {
        return strdup("failed to create temporary file");
    }
    
    fp = fdopen(fd, "w");
    if (!fp) {
        close(fd);
        return strdup("failed to open temporary file for writing");
    }
    
    for (int i = 0; i < count; i++) {
        fprintf(fp, "%s\n", files[i].name);
    }
    
    fclose(fp);
    return NULL;
}

char *invoke_editor(const char *temp_path) {
    char *editor = getenv("EDITOR");
    pid_t pid;
    int status;
    
    if (!editor || strlen(editor) == 0) {
        return strdup("no EDITOR environment variable set");
    }
    
    pid = fork();
    if (pid == -1) {
        return strdup("failed to fork process for editor");
    }
    
    if (pid == 0) {
        execlp(editor, editor, temp_path, NULL);
        exit(1);
    }
    
    waitpid(pid, &status, 0);
    if (status != 0) {
        return strdup("editor exited with non-zero status");
    }
    
    return NULL;
}

char *read_edited_files(const char *temp_path, file_entry **new_files, int *count) {
    FILE *fp;
    char *line = NULL;
    size_t line_len = 0;
    ssize_t read;
    int capacity = 16;
    *count = 0;
    
    *new_files = malloc(capacity * sizeof(file_entry));
    if (!*new_files) {
        return strdup("failed to allocate memory for edited file list");
    }
    
    fp = fopen(temp_path, "r");
    if (!fp) {
        free(*new_files);
        *new_files = NULL;
        return strdup("failed to reopen temporary file for reading");
    }
    
    while ((read = getline(&line, &line_len, fp)) != -1) {
        if (read > 0 && line[read-1] == '\n') {
            line[read-1] = '\0';
            read--;
        }
        if (read > 0) {
            if (*count >= capacity) {
                capacity *= 2;
                file_entry *new_entries = realloc(*new_files, capacity * sizeof(file_entry));
                if (!new_entries) {
                    fclose(fp);
                    free(line);
                    for (int i = 0; i < *count; i++) {
                        free((*new_files)[i].name);
                    }
                    free(*new_files);
                    *new_files = NULL;
                    return strdup("failed to reallocate memory for edited file list");
                }
                *new_files = new_entries;
            }
            (*new_files)[*count].name = strdup(line);
            if (!(*new_files)[*count].name) {
                fclose(fp);
                free(line);
                for (int i = 0; i < *count; i++) {
                    free((*new_files)[i].name);
                }
                free(*new_files);
                *new_files = NULL;
                return strdup("failed to allocate memory for edited filename");
            }
            (*count)++;
        }
    }
    
    free(line);
    fclose(fp);
    return NULL;
}

char *analyze_renames(file_entry *old_files, file_entry *new_files, int count, 
                     rename_entry **renames, int *rename_count, int *tricky) {
    int *orig_count = calloc(count, sizeof(int));
    int *dest_count = calloc(count, sizeof(int));
    int *unchanged = calloc(count, sizeof(int));
    int capacity = count;
    char *error = NULL;
    
    *renames = malloc(capacity * sizeof(rename_entry));
    if (!orig_count || !dest_count || !unchanged || !*renames) {
        free(orig_count);
        free(dest_count);
        free(unchanged);
        free(*renames);
        *renames = NULL;
        return strdup("failed to allocate memory for rename analysis");
    }
    
    *rename_count = 0;
    *tricky = 0;
    
    for (int i = 0; i < count; i++) {
        if (strcmp(old_files[i].name, new_files[i].name) != 0) {
            (*renames)[*rename_count].old_name = strdup(old_files[i].name);
            (*renames)[*rename_count].new_name = strdup(new_files[i].name);
            if (!(*renames)[*rename_count].old_name || !(*renames)[*rename_count].new_name) {
                error = strdup("failed to allocate memory for rename entry");
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
    
    if (!error) {
        // Check for duplicate new names
        for (int i = 0; i < *rename_count && !error; i++) {
            for (int j = i + 1; j < *rename_count; j++) {
                if (strcmp((*renames)[i].new_name, (*renames)[j].new_name) == 0) {
                    error = strdup("multiple files would be renamed to the same name");
                    goto cleanup;
                }
            }
        }
        
        // Check for overwriting unchanged files and detect tricky renames
        for (int i = 0; i < count && !error; i++) {
            for (int j = 0; j < *rename_count && !error; j++) {
                if (strcmp((*renames)[j].new_name, old_files[i].name) == 0 && unchanged[i]) {
                    error = strdup("rename would overwrite an existing unchanged file");
                    break;
                }
                
                if (strcmp((*renames)[j].new_name, old_files[i].name) == 0 && orig_count[i]) {
                    *tricky = 1;
                }
            }
        }
    }
    
cleanup:
    if (error && *renames) {
        free_rename_entries(*renames, *rename_count);
        *renames = NULL;
    }
    free(orig_count);
    free(dest_count);
    free(unchanged);
    return error;
}

char *perform_renames(rename_entry *renames, int rename_count, int tricky) {
    char temp_dir[] = "./emv_temp_XXXXXX";
    
    if (tricky) {
        if (mkdtemp(temp_dir) == NULL) {
            return strdup("failed to create temporary directory for tricky renames");
        }
        
        for (int i = 0; i < rename_count; i++) {
            char *temp_path;
            asprintf(&temp_path, "%s/%s", temp_dir, renames[i].old_name);
            if (!temp_path) {
                rmdir(temp_dir);
                return strdup("failed to allocate memory for temporary path");
            }
            
            if (rename(renames[i].old_name, temp_path) != 0) {
                char *err;
                asprintf(&err, "failed to move %s to temporary location: %s", 
                        renames[i].old_name, strerror(errno));
                free(temp_path);
                rmdir(temp_dir);
                return err;
            }
            
            free(renames[i].old_name);
            renames[i].old_name = temp_path;
        }
    }
    
    for (int i = 0; i < rename_count; i++) {
        if (rename(renames[i].old_name, renames[i].new_name) != 0) {
            if (tricky) rmdir(temp_dir);
            char *err;
            asprintf(&err, "failed to rename %s to %s: %s", 
                    renames[i].old_name, renames[i].new_name, strerror(errno));
            return err;
        }
    }
    
    if (tricky) {
        if (rmdir(temp_dir) != 0) {
            char *err;
            asprintf(&err, "failed to remove temporary directory %s: %s", 
                    temp_dir, strerror(errno));
            return err;
        }
    }
    
    return NULL;
}

int main(int argc, char *argv[]) {
    file_entry *old_files = NULL;
    file_entry *new_files = NULL;
    rename_entry *renames = NULL;
    char temp_path[] = "/tmp/emv_XXXXXX";
    char *error;
    int old_count, new_count, rename_count, tricky;
    
    if (argc > 1) {
        if (chdir(argv[1]) != 0) {
            fprintf(stderr, "failed to change to directory %s: %s\n", argv[1], strerror(errno));
            return 1;
        }
    }
    
    error = read_directory(".", &old_files, &old_count);
    if (error) {
        fprintf(stderr, "%s\n", error);
        free(error);
        return 1;
    }
    
    error = create_temp_file(old_files, old_count, temp_path);
    if (error) {
        fprintf(stderr, "%s\n", error);
        free(error);
        free_file_entries(old_files, old_count);
        return 1;
    }
    
    error = invoke_editor(temp_path);
    if (error) {
        fprintf(stderr, "%s\n", error);
        free(error);
        free_file_entries(old_files, old_count);
        unlink(temp_path);
        return 1;
    }
    
    error = read_edited_files(temp_path, &new_files, &new_count);
    unlink(temp_path);
    if (error) {
        fprintf(stderr, "%s\n", error);
        free(error);
        free_file_entries(old_files, old_count);
        return 1;
    }
    
    if (old_count != new_count) {
        fprintf(stderr, "file count changed: had %d files, now have %d files\n", old_count, new_count);
        free_file_entries(old_files, old_count);
        free_file_entries(new_files, new_count);
        return 1;
    }
    
    error = analyze_renames(old_files, new_files, old_count, &renames, &rename_count, &tricky);
    if (error) {
        fprintf(stderr, "%s\n", error);
        free(error);
        free_file_entries(old_files, old_count);
        free_file_entries(new_files, new_count);
        return 1;
    }
    
    error = perform_renames(renames, rename_count, tricky);
    if (error) {
        fprintf(stderr, "%s\n", error);
        free(error);
        free_file_entries(old_files, old_count);
        free_file_entries(new_files, new_count);
        free_rename_entries(renames, rename_count);
        return 1;
    }
    
    free_file_entries(old_files, old_count);
    free_file_entries(new_files, new_count);
    free_rename_entries(renames, rename_count);
    return 0;
}
