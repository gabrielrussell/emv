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

#define MAX_FILES 1000
#define MAX_FILENAME 256
#define MAX_PATH 1024

typedef struct {
    char name[MAX_FILENAME];
} file_entry;

typedef struct {
    char old_name[MAX_FILENAME];
    char new_name[MAX_FILENAME];
} rename_entry;

static int compare_strings(const void *a, const void *b) {
    return strcmp(((file_entry*)a)->name, ((file_entry*)b)->name);
}

int read_directory(const char *path, file_entry *files) {
    DIR *dir;
    struct dirent *entry;
    int count = 0;
    
    dir = opendir(path);
    if (!dir) {
        perror("opendir");
        return -1;
    }
    
    while ((entry = readdir(dir)) != NULL && count < MAX_FILES) {
        if (entry->d_name[0] != '.' && strchr(entry->d_name, '\n') == NULL) {
            strncpy(files[count].name, entry->d_name, MAX_FILENAME - 1);
            files[count].name[MAX_FILENAME - 1] = '\0';
            count++;
        }
    }
    
    closedir(dir);
    qsort(files, count, sizeof(file_entry), compare_strings);
    return count;
}

int create_temp_file(file_entry *files, int count, char *temp_path) {
    int fd;
    FILE *fp;
    
    strcpy(temp_path, "/tmp/emv_XXXXXX");
    fd = mkstemp(temp_path);
    if (fd == -1) {
        perror("mkstemp");
        return -1;
    }
    
    fp = fdopen(fd, "w");
    if (!fp) {
        perror("fdopen");
        close(fd);
        return -1;
    }
    
    for (int i = 0; i < count; i++) {
        fprintf(fp, "%s\n", files[i].name);
    }
    
    fclose(fp);
    return 0;
}

int invoke_editor(const char *temp_path) {
    char *editor = getenv("EDITOR");
    pid_t pid;
    int status;
    
    if (!editor || strlen(editor) == 0) {
        fprintf(stderr, "no EDITOR environment set\n");
        return -1;
    }
    
    pid = fork();
    if (pid == -1) {
        perror("fork");
        return -1;
    }
    
    if (pid == 0) {
        execlp(editor, editor, temp_path, NULL);
        perror("exec");
        exit(1);
    }
    
    waitpid(pid, &status, 0);
    if (status != 0) {
        fprintf(stderr, "editor failure\n");
        return -1;
    }
    
    return 0;
}

int read_edited_files(const char *temp_path, file_entry *new_files) {
    FILE *fp;
    char line[MAX_FILENAME];
    int count = 0;
    
    fp = fopen(temp_path, "r");
    if (!fp) {
        perror("fopen");
        return -1;
    }
    
    while (fgets(line, sizeof(line), fp) && count < MAX_FILES) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) > 0) {
            strncpy(new_files[count].name, line, MAX_FILENAME - 1);
            new_files[count].name[MAX_FILENAME - 1] = '\0';
            count++;
        }
    }
    
    fclose(fp);
    return count;
}

int analyze_renames(file_entry *old_files, file_entry *new_files, int count, 
                   rename_entry *renames, int *rename_count, int *tricky) {
    int *orig_count = calloc(count, sizeof(int));
    int *dest_count = calloc(count, sizeof(int));
    int *unchanged = calloc(count, sizeof(int));
    
    if (!orig_count || !dest_count || !unchanged) {
        free(orig_count);
        free(dest_count);
        free(unchanged);
        return -1;
    }
    
    *rename_count = 0;
    *tricky = 0;
    
    for (int i = 0; i < count; i++) {
        if (strcmp(old_files[i].name, new_files[i].name) != 0) {
            strcpy(renames[*rename_count].old_name, old_files[i].name);
            strcpy(renames[*rename_count].new_name, new_files[i].name);
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
    
    for (int i = 0; i < count; i++) {
        if (dest_count[i] > 1) {
            fprintf(stderr, "non-unique renames\n");
            free(orig_count);
            free(dest_count);
            free(unchanged);
            return -1;
        }
        
        for (int j = 0; j < *rename_count; j++) {
            if (strcmp(renames[j].new_name, old_files[i].name) == 0 && unchanged[i]) {
                fprintf(stderr, "new file would overwrite existing file\n");
                free(orig_count);
                free(dest_count);
                free(unchanged);
                return -1;
            }
            
            if (strcmp(renames[j].new_name, old_files[i].name) == 0 && orig_count[i]) {
                *tricky = 1;
            }
        }
    }
    
    free(orig_count);
    free(dest_count);
    free(unchanged);
    return 0;
}

int perform_renames(rename_entry *renames, int rename_count, int tricky) {
    char temp_dir[MAX_PATH] = "./emv_temp_XXXXXX";
    
    if (tricky) {
        if (mkdtemp(temp_dir) == NULL) {
            perror("mkdtemp");
            return -1;
        }
        
        for (int i = 0; i < rename_count; i++) {
            char temp_path[MAX_PATH];
            snprintf(temp_path, sizeof(temp_path), "%s/%s", temp_dir, renames[i].old_name);
            
            if (rename(renames[i].old_name, temp_path) != 0) {
                perror("rename to temp");
                rmdir(temp_dir);
                return -1;
            }
            
            strcpy(renames[i].old_name, temp_path);
        }
    }
    
    for (int i = 0; i < rename_count; i++) {
        if (rename(renames[i].old_name, renames[i].new_name) != 0) {
            fprintf(stderr, "%s\nrename(%s,%s)\n", strerror(errno),
                    renames[i].old_name, renames[i].new_name);
            if (tricky) rmdir(temp_dir);
            return -1;
        }
    }
    
    if (tricky) {
        if (rmdir(temp_dir) != 0) {
            perror("rmdir");
            return -1;
        }
    }
    
    return 0;
}

int main(int argc, char *argv[]) {
    file_entry old_files[MAX_FILES];
    file_entry new_files[MAX_FILES];
    rename_entry renames[MAX_FILES];
    char temp_path[MAX_PATH];
    int old_count, new_count, rename_count, tricky;
    
    if (argc > 1) {
        if (chdir(argv[1]) != 0) {
            perror("chdir");
            return 1;
        }
    }
    
    old_count = read_directory(".", old_files);
    if (old_count < 0) return 1;
    
    if (create_temp_file(old_files, old_count, temp_path) != 0) return 1;
    
    if (invoke_editor(temp_path) != 0) {
        unlink(temp_path);
        return 1;
    }
    
    new_count = read_edited_files(temp_path, new_files);
    unlink(temp_path);
    
    if (new_count < 0) return 1;
    
    if (old_count != new_count) {
        fprintf(stderr, "lost or gained something\n");
        return 1;
    }
    
    if (analyze_renames(old_files, new_files, old_count, renames, &rename_count, &tricky) != 0) {
        return 1;
    }
    
    if (perform_renames(renames, rename_count, tricky) != 0) {
        return 1;
    }
    
    return 0;
}
