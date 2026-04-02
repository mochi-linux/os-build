/*
 * MochiOS Application Launcher
 * 
 * Launches .app bundles with proper library paths and environment setup.
 * 
 * Bundle Structure:
 *   Foo.app/
 *     - Exec/{arch}/{binary}     - Executable binary (ELF)
 *     - Library/                 - Shared libraries
 *     - Resources/               - Application resources
 *     - Manifest.yml             - Application metadata
 * 
 * Usage:
 *   launcher /Applications/Foo.app [args...]
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <libgen.h>

#define MAX_PATH 4096
#define MAX_LINE 1024
#define ARCH "x86_64"

typedef struct {
    char bundle_path[MAX_PATH];
    char exec_path[MAX_PATH];
    char lib_path[MAX_PATH];
    char resources_path[MAX_PATH];
    char manifest_path[MAX_PATH];
    char app_name[256];
    char ld_library_path[MAX_PATH];
} AppBundle;

/* Print error message and exit */
static void die(const char *msg) {
    fprintf(stderr, "launcher: error: %s\n", msg);
    exit(1);
}

/* Print error with errno and exit */
static void die_errno(const char *msg) {
    perror(msg);
    exit(1);
}

/* Check if path exists */
static int path_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

/* Check if path is a directory */
static int is_directory(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0)
        return 0;
    return S_ISDIR(st.st_mode);
}

/* Check if path is executable */
static int is_executable(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0)
        return 0;
    return (st.st_mode & S_IXUSR) || (st.st_mode & S_IXGRP) || (st.st_mode & S_IXOTH);
}

/* Resolve absolute path */
static void resolve_path(const char *path, char *resolved) {
    if (realpath(path, resolved) == NULL) {
        die_errno("realpath");
    }
}

/* Extract app name from bundle path (e.g., "Foo.app" -> "Foo") */
static void extract_app_name(const char *bundle_path, char *app_name) {
    char *base = basename((char *)bundle_path);
    char *dot = strrchr(base, '.');
    
    if (dot && strcmp(dot, ".app") == 0) {
        size_t len = dot - base;
        strncpy(app_name, base, len);
        app_name[len] = '\0';
    } else {
        strncpy(app_name, base, 255);
        app_name[255] = '\0';
    }
}

/* Find executable in Exec/{arch}/ directory */
static int find_executable(AppBundle *bundle) {
    char exec_dir[MAX_PATH];
    DIR *dir;
    struct dirent *entry;
    int found = 0;
    
    snprintf(exec_dir, sizeof(exec_dir), "%s/Exec/%s", bundle->bundle_path, ARCH);
    
    if (!is_directory(exec_dir)) {
        fprintf(stderr, "launcher: warning: Exec/%s directory not found, trying Exec/\n", ARCH);
        snprintf(exec_dir, sizeof(exec_dir), "%s/Exec", bundle->bundle_path);
        
        if (!is_directory(exec_dir)) {
            return 0;
        }
    }
    
    dir = opendir(exec_dir);
    if (!dir) {
        return 0;
    }
    
    /* Find first executable file */
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.')
            continue;
            
        snprintf(bundle->exec_path, sizeof(bundle->exec_path), 
                 "%s/%s", exec_dir, entry->d_name);
        
        if (is_executable(bundle->exec_path)) {
            found = 1;
            break;
        }
    }
    
    closedir(dir);
    return found;
}

/* Parse Manifest.yml for additional configuration */
static void parse_manifest(AppBundle *bundle) {
    FILE *fp;
    char line[MAX_LINE];
    char key[256], value[MAX_PATH];
    
    fp = fopen(bundle->manifest_path, "r");
    if (!fp) {
        /* Manifest is optional */
        return;
    }
    
    while (fgets(line, sizeof(line), fp)) {
        /* Skip comments and empty lines */
        if (line[0] == '#' || line[0] == '\n')
            continue;
        
        /* Simple key: value parser */
        if (sscanf(line, "%255[^:]: %4095[^\n]", key, value) == 2) {
            /* Trim leading/trailing whitespace from value */
            char *v = value;
            while (*v == ' ' || *v == '\t') v++;
            
            if (strcmp(key, "LD_LIBRARY_PATH") == 0) {
                /* Append to existing LD_LIBRARY_PATH */
                if (strlen(bundle->ld_library_path) > 0) {
                    strncat(bundle->ld_library_path, ":", sizeof(bundle->ld_library_path) - strlen(bundle->ld_library_path) - 1);
                }
                strncat(bundle->ld_library_path, v, sizeof(bundle->ld_library_path) - strlen(bundle->ld_library_path) - 1);
            }
        }
    }
    
    fclose(fp);
}

/* Initialize app bundle structure */
static void init_bundle(const char *bundle_path, AppBundle *bundle) {
    memset(bundle, 0, sizeof(AppBundle));
    
    /* Resolve absolute bundle path */
    resolve_path(bundle_path, bundle->bundle_path);
    
    /* Check if bundle exists and is a directory */
    if (!is_directory(bundle->bundle_path)) {
        die("bundle path is not a directory");
    }
    
    /* Extract app name */
    extract_app_name(bundle->bundle_path, bundle->app_name);
    
    /* Set up paths */
    snprintf(bundle->lib_path, sizeof(bundle->lib_path), 
             "%s/Library", bundle->bundle_path);
    snprintf(bundle->resources_path, sizeof(bundle->resources_path), 
             "%s/Resources", bundle->bundle_path);
    snprintf(bundle->manifest_path, sizeof(bundle->manifest_path), 
             "%s/Manifest.yml", bundle->bundle_path);
    
    /* Find executable */
    if (!find_executable(bundle)) {
        die("no executable found in bundle");
    }
    
    /* Build LD_LIBRARY_PATH */
    if (is_directory(bundle->lib_path)) {
        snprintf(bundle->ld_library_path, sizeof(bundle->ld_library_path), 
                 "%s", bundle->lib_path);
    }
    
    /* Parse manifest for additional configuration */
    if (path_exists(bundle->manifest_path)) {
        parse_manifest(bundle);
    }
}

/* Set up environment for app execution */
static void setup_environment(AppBundle *bundle) {
    /* Set LD_LIBRARY_PATH */
    if (strlen(bundle->ld_library_path) > 0) {
        const char *existing = getenv("LD_LIBRARY_PATH");
        if (existing) {
            char new_path[MAX_PATH * 2];
            snprintf(new_path, sizeof(new_path), "%s:%s", 
                     bundle->ld_library_path, existing);
            setenv("LD_LIBRARY_PATH", new_path, 1);
        } else {
            setenv("LD_LIBRARY_PATH", bundle->ld_library_path, 1);
        }
    }
    
    /* Set APP_BUNDLE for the application to know its bundle path */
    setenv("APP_BUNDLE", bundle->bundle_path, 1);
    
    /* Set APP_RESOURCES for easy resource access */
    if (is_directory(bundle->resources_path)) {
        setenv("APP_RESOURCES", bundle->resources_path, 1);
    }
    
    /* Set APP_NAME */
    setenv("APP_NAME", bundle->app_name, 1);
}

/* Print bundle information */
static void print_bundle_info(AppBundle *bundle) {
    printf("MochiOS Application Launcher\n");
    printf("============================\n");
    printf("Bundle:      %s\n", bundle->bundle_path);
    printf("App Name:    %s\n", bundle->app_name);
    printf("Executable:  %s\n", bundle->exec_path);
    if (strlen(bundle->ld_library_path) > 0)
        printf("Libraries:   %s\n", bundle->ld_library_path);
    if (is_directory(bundle->resources_path))
        printf("Resources:   %s\n", bundle->resources_path);
    printf("\n");
}

/* Show usage */
static void usage(const char *prog) {
    fprintf(stderr, "Usage: %s [OPTIONS] <bundle.app> [args...]\n", prog);
    fprintf(stderr, "\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -i, --info     Show bundle information and exit\n");
    fprintf(stderr, "  -h, --help     Show this help message\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s /Applications/TextEdit.app\n", prog);
    fprintf(stderr, "  %s /Applications/Calculator.app --version\n", prog);
    fprintf(stderr, "  %s --info /Applications/Terminal.app\n", prog);
    exit(1);
}

int main(int argc, char *argv[]) {
    AppBundle bundle;
    int show_info = 0;
    int arg_start = 1;
    
    /* Parse options */
    if (argc < 2) {
        usage(argv[0]);
    }
    
    if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        usage(argv[0]);
    }
    
    if (strcmp(argv[1], "-i") == 0 || strcmp(argv[1], "--info") == 0) {
        show_info = 1;
        arg_start = 2;
        if (argc < 3) {
            usage(argv[0]);
        }
    }
    
    /* Initialize bundle */
    init_bundle(argv[arg_start], &bundle);
    
    /* Show info and exit if requested */
    if (show_info) {
        print_bundle_info(&bundle);
        return 0;
    }
    
    /* Set up environment */
    setup_environment(&bundle);
    
    /* Build argv for exec */
    char **exec_argv = malloc(sizeof(char *) * (argc - arg_start + 1));
    if (!exec_argv) {
        die_errno("malloc");
    }
    
    exec_argv[0] = bundle.exec_path;
    for (int i = arg_start + 1; i < argc; i++) {
        exec_argv[i - arg_start] = argv[i];
    }
    exec_argv[argc - arg_start] = NULL;
    
    /* Execute the application */
    execv(bundle.exec_path, exec_argv);
    
    /* If we get here, exec failed */
    die_errno("execv");
    
    return 1;
}
