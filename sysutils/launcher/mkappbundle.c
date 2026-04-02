/*
 * MochiOS Application Bundle Creator
 * 
 * Creates .app bundles from compiled ELF binaries with proper directory structure.
 * 
 * Usage:
 *   mkappbundle -n AppName -e binary [-l lib1.so -l lib2.so] [-r resources/] [-o output/]
 * 
 * Creates:
 *   AppName.app/
 *     - Exec/{arch}/{binary}
 *     - Library/ (shared libraries)
 *     - Resources/ (application resources)
 *     - Manifest.yml
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
#include <getopt.h>
#include <time.h>
#include <stdarg.h>

#define MAX_PATH 4096
#define MAX_LIBS 256
#define MAX_RESOURCES 256
#define ARCH "x86_64"

typedef struct {
    char app_name[256];
    char executable[MAX_PATH];
    char libraries[MAX_LIBS][MAX_PATH];
    int lib_count;
    char resources[MAX_RESOURCES][MAX_PATH];
    int resource_count;
    char output_dir[MAX_PATH];
    char bundle_path[MAX_PATH];
    char version[64];
    char description[512];
    int verbose;
} BundleConfig;

/* Print error and exit */
static void die(const char *msg) {
    fprintf(stderr, "mkappbundle: error: %s\n", msg);
    exit(1);
}

/* Print error with errno and exit */
static void die_errno(const char *msg) {
    perror(msg);
    exit(1);
}

/* Verbose logging */
static void vlog(BundleConfig *cfg, const char *fmt, ...) {
    if (!cfg->verbose)
        return;
    
    va_list args;
    va_start(args, fmt);
    printf("  ");
    vprintf(fmt, args);
    printf("\n");
    va_end(args);
}

/* Create directory recursively */
static int mkdir_p(const char *path) {
    char tmp[MAX_PATH];
    char *p = NULL;
    size_t len;
    
    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    
    if (tmp[len - 1] == '/')
        tmp[len - 1] = 0;
    
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST)
        return -1;
    
    return 0;
}

/* Check if file exists */
static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* Check if directory exists */
static int dir_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

/* Copy file */
static int copy_file(const char *src, const char *dst, int preserve_perms) {
    FILE *in, *out;
    char buf[8192];
    size_t n;
    struct stat st;
    
    in = fopen(src, "rb");
    if (!in)
        return -1;
    
    out = fopen(dst, "wb");
    if (!out) {
        fclose(in);
        return -1;
    }
    
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
        if (fwrite(buf, 1, n, out) != n) {
            fclose(in);
            fclose(out);
            return -1;
        }
    }
    
    fclose(in);
    fclose(out);
    
    /* Preserve permissions if requested */
    if (preserve_perms && stat(src, &st) == 0) {
        chmod(dst, st.st_mode);
    }
    
    return 0;
}

/* Copy directory recursively */
static int copy_directory(const char *src, const char *dst) {
    DIR *dir;
    struct dirent *entry;
    char src_path[MAX_PATH];
    char dst_path[MAX_PATH];
    struct stat st;
    
    if (mkdir_p(dst) != 0)
        return -1;
    
    dir = opendir(src);
    if (!dir)
        return -1;
    
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        
        snprintf(src_path, sizeof(src_path), "%s/%s", src, entry->d_name);
        snprintf(dst_path, sizeof(dst_path), "%s/%s", dst, entry->d_name);
        
        if (stat(src_path, &st) != 0)
            continue;
        
        if (S_ISDIR(st.st_mode)) {
            if (copy_directory(src_path, dst_path) != 0) {
                closedir(dir);
                return -1;
            }
        } else if (S_ISREG(st.st_mode)) {
            if (copy_file(src_path, dst_path, 1) != 0) {
                closedir(dir);
                return -1;
            }
        }
    }
    
    closedir(dir);
    return 0;
}

/* Create bundle directory structure */
static void create_bundle_structure(BundleConfig *cfg) {
    char path[MAX_PATH];
    
    printf("Creating bundle: %s\n", cfg->bundle_path);
    
    /* Create main bundle directory */
    if (mkdir_p(cfg->bundle_path) != 0)
        die_errno("Failed to create bundle directory");
    
    /* Create Exec/{arch} directory */
    snprintf(path, sizeof(path), "%s/Exec/%s", cfg->bundle_path, ARCH);
    vlog(cfg, "Creating %s", path);
    if (mkdir_p(path) != 0)
        die_errno("Failed to create Exec directory");
    
    /* Create Library directory */
    snprintf(path, sizeof(path), "%s/Library", cfg->bundle_path);
    vlog(cfg, "Creating %s", path);
    if (mkdir_p(path) != 0)
        die_errno("Failed to create Library directory");
    
    /* Create Resources directory */
    snprintf(path, sizeof(path), "%s/Resources", cfg->bundle_path);
    vlog(cfg, "Creating %s", path);
    if (mkdir_p(path) != 0)
        die_errno("Failed to create Resources directory");
}

/* Copy executable to bundle */
static void copy_executable(BundleConfig *cfg) {
    char dst[MAX_PATH];
    char *exe_name;
    
    if (!file_exists(cfg->executable)) {
        fprintf(stderr, "Error: Executable not found: %s\n", cfg->executable);
        die("Executable file does not exist");
    }
    
    exe_name = basename(cfg->executable);
    snprintf(dst, sizeof(dst), "%s/Exec/%s/%s", cfg->bundle_path, ARCH, exe_name);
    
    printf("Copying executable: %s -> %s\n", cfg->executable, dst);
    
    if (copy_file(cfg->executable, dst, 1) != 0)
        die_errno("Failed to copy executable");
    
    /* Ensure executable permissions */
    chmod(dst, 0755);
}

/* Copy libraries to bundle */
static void copy_libraries(BundleConfig *cfg) {
    char dst[MAX_PATH];
    char *lib_name;
    
    if (cfg->lib_count == 0) {
        vlog(cfg, "No libraries to copy");
        return;
    }
    
    printf("Copying %d libraries...\n", cfg->lib_count);
    
    for (int i = 0; i < cfg->lib_count; i++) {
        if (!file_exists(cfg->libraries[i])) {
            fprintf(stderr, "Warning: Library not found: %s (skipping)\n", cfg->libraries[i]);
            continue;
        }
        
        lib_name = basename(cfg->libraries[i]);
        snprintf(dst, sizeof(dst), "%s/Library/%s", cfg->bundle_path, lib_name);
        
        vlog(cfg, "Copying %s", lib_name);
        
        if (copy_file(cfg->libraries[i], dst, 1) != 0) {
            fprintf(stderr, "Warning: Failed to copy library: %s\n", cfg->libraries[i]);
        }
    }
}

/* Copy resources to bundle */
static void copy_resources(BundleConfig *cfg) {
    char dst[MAX_PATH];
    char *res_name;
    struct stat st;
    
    if (cfg->resource_count == 0) {
        vlog(cfg, "No resources to copy");
        return;
    }
    
    printf("Copying %d resources...\n", cfg->resource_count);
    
    for (int i = 0; i < cfg->resource_count; i++) {
        if (stat(cfg->resources[i], &st) != 0) {
            fprintf(stderr, "Warning: Resource not found: %s (skipping)\n", cfg->resources[i]);
            continue;
        }
        
        res_name = basename(cfg->resources[i]);
        snprintf(dst, sizeof(dst), "%s/Resources/%s", cfg->bundle_path, res_name);
        
        if (S_ISDIR(st.st_mode)) {
            vlog(cfg, "Copying directory %s", res_name);
            if (copy_directory(cfg->resources[i], dst) != 0) {
                fprintf(stderr, "Warning: Failed to copy resource directory: %s\n", cfg->resources[i]);
            }
        } else {
            vlog(cfg, "Copying file %s", res_name);
            if (copy_file(cfg->resources[i], dst, 1) != 0) {
                fprintf(stderr, "Warning: Failed to copy resource file: %s\n", cfg->resources[i]);
            }
        }
    }
}

/* Create Manifest.yml */
static void create_manifest(BundleConfig *cfg) {
    char manifest_path[MAX_PATH];
    FILE *fp;
    time_t now;
    char timestamp[64];
    
    snprintf(manifest_path, sizeof(manifest_path), "%s/Manifest.yml", cfg->bundle_path);
    
    printf("Creating manifest: %s\n", manifest_path);
    
    fp = fopen(manifest_path, "w");
    if (!fp)
        die_errno("Failed to create manifest");
    
    time(&now);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
    
    fprintf(fp, "# MochiOS Application Bundle Manifest\n");
    fprintf(fp, "# Generated by mkappbundle on %s\n\n", timestamp);
    fprintf(fp, "Name: %s\n", cfg->app_name);
    
    if (strlen(cfg->version) > 0)
        fprintf(fp, "Version: %s\n", cfg->version);
    else
        fprintf(fp, "Version: 1.0.0\n");
    
    if (strlen(cfg->description) > 0)
        fprintf(fp, "Description: %s\n", cfg->description);
    
    fprintf(fp, "Architecture: %s\n", ARCH);
    fprintf(fp, "Executable: Exec/%s/%s\n", ARCH, basename(cfg->executable));
    
    if (cfg->lib_count > 0) {
        fprintf(fp, "\n# Additional library paths (optional)\n");
        fprintf(fp, "# LD_LIBRARY_PATH: /usr/local/lib\n");
    }
    
    fclose(fp);
}

/* Show usage */
static void usage(const char *prog) {
    fprintf(stderr, "MochiOS Application Bundle Creator\n");
    fprintf(stderr, "Usage: %s [OPTIONS]\n\n", prog);
    fprintf(stderr, "Required:\n");
    fprintf(stderr, "  -n, --name NAME        Application name (e.g., 'TextEdit')\n");
    fprintf(stderr, "  -e, --exec FILE        Executable ELF binary\n\n");
    fprintf(stderr, "Optional:\n");
    fprintf(stderr, "  -l, --lib FILE         Add shared library (can be used multiple times)\n");
    fprintf(stderr, "  -r, --resource PATH    Add resource file or directory (can be used multiple times)\n");
    fprintf(stderr, "  -o, --output DIR       Output directory (default: current directory)\n");
    fprintf(stderr, "  -v, --version VER      Application version (default: 1.0.0)\n");
    fprintf(stderr, "  -d, --desc TEXT        Application description\n");
    fprintf(stderr, "  -V, --verbose          Verbose output\n");
    fprintf(stderr, "  -h, --help             Show this help\n\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s -n Calculator -e build/calc\n", prog);
    fprintf(stderr, "  %s -n TextEdit -e textedit -l libspell.so -r icons/\n", prog);
    fprintf(stderr, "  %s -n MyApp -e myapp -l lib1.so -l lib2.so -r data/ -o ~/Applications/\n", prog);
    exit(1);
}

int main(int argc, char *argv[]) {
    BundleConfig cfg;
    int opt;
    
    static struct option long_options[] = {
        {"name",     required_argument, 0, 'n'},
        {"exec",     required_argument, 0, 'e'},
        {"lib",      required_argument, 0, 'l'},
        {"resource", required_argument, 0, 'r'},
        {"output",   required_argument, 0, 'o'},
        {"version",  required_argument, 0, 'v'},
        {"desc",     required_argument, 0, 'd'},
        {"verbose",  no_argument,       0, 'V'},
        {"help",     no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    /* Initialize config */
    memset(&cfg, 0, sizeof(cfg));
    strcpy(cfg.output_dir, ".");
    
    /* Parse arguments */
    while ((opt = getopt_long(argc, argv, "n:e:l:r:o:v:d:Vh", long_options, NULL)) != -1) {
        switch (opt) {
            case 'n':
                strncpy(cfg.app_name, optarg, sizeof(cfg.app_name) - 1);
                break;
            case 'e':
                strncpy(cfg.executable, optarg, sizeof(cfg.executable) - 1);
                break;
            case 'l':
                if (cfg.lib_count >= MAX_LIBS) {
                    die("Too many libraries (max 256)");
                }
                strncpy(cfg.libraries[cfg.lib_count++], optarg, MAX_PATH - 1);
                break;
            case 'r':
                if (cfg.resource_count >= MAX_RESOURCES) {
                    die("Too many resources (max 256)");
                }
                strncpy(cfg.resources[cfg.resource_count++], optarg, MAX_PATH - 1);
                break;
            case 'o':
                strncpy(cfg.output_dir, optarg, sizeof(cfg.output_dir) - 1);
                break;
            case 'v':
                strncpy(cfg.version, optarg, sizeof(cfg.version) - 1);
                break;
            case 'd':
                strncpy(cfg.description, optarg, sizeof(cfg.description) - 1);
                break;
            case 'V':
                cfg.verbose = 1;
                break;
            case 'h':
            default:
                usage(argv[0]);
        }
    }
    
    /* Validate required arguments */
    if (strlen(cfg.app_name) == 0) {
        fprintf(stderr, "Error: Application name is required (-n)\n\n");
        usage(argv[0]);
    }
    
    if (strlen(cfg.executable) == 0) {
        fprintf(stderr, "Error: Executable is required (-e)\n\n");
        usage(argv[0]);
    }
    
    /* Build bundle path */
    snprintf(cfg.bundle_path, sizeof(cfg.bundle_path), "%s/%s.app", 
             cfg.output_dir, cfg.app_name);
    
    /* Check if bundle already exists */
    if (dir_exists(cfg.bundle_path)) {
        fprintf(stderr, "Error: Bundle already exists: %s\n", cfg.bundle_path);
        fprintf(stderr, "Remove it first or choose a different output directory.\n");
        exit(1);
    }
    
    /* Create bundle */
    printf("MochiOS Application Bundle Creator\n");
    printf("===================================\n");
    printf("App Name:    %s\n", cfg.app_name);
    printf("Executable:  %s\n", cfg.executable);
    printf("Output:      %s\n", cfg.bundle_path);
    printf("\n");
    
    create_bundle_structure(&cfg);
    copy_executable(&cfg);
    copy_libraries(&cfg);
    copy_resources(&cfg);
    create_manifest(&cfg);
    
    printf("\n");
    printf("✓ Bundle created successfully: %s\n", cfg.bundle_path);
    printf("\n");
    printf("To launch: launcher %s\n", cfg.bundle_path);
    
    return 0;
}
