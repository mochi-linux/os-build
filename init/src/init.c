/*
 * MochiOS Init - System Initialization Process
 * 
 * A minimal init system (PID 1) that:
 * - Mounts essential filesystems
 * - Sets up the environment
 * - Spawns getty on consoles
 * - Handles process reaping
 * - Manages system shutdown/reboot
 */

#define _GNU_SOURCE
#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>

#define INIT_VERSION "1.0"
#define MAX_RESPAWN 5
#define RESPAWN_WINDOW 60

/* Service definition */
typedef struct {
    const char *name;
    const char *command;
    char *const *argv;
    pid_t pid;
    int respawn;
    time_t last_spawn;
    int spawn_count;
} service_t;

/* Global state */
static volatile sig_atomic_t got_sigchld = 0;
static volatile sig_atomic_t do_shutdown = 0;
static volatile sig_atomic_t do_reboot = 0;

/* Logging */
static void log_msg(const char *level, const char *msg) {
    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char timestamp[32];
    
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm);
    fprintf(stderr, "[%s] [%s] %s\n", timestamp, level, msg);
}

static void log_info(const char *msg) { log_msg("INFO", msg); }
static void log_error(const char *msg) { log_msg("ERROR", msg); }
static void log_warn(const char *msg) { log_msg("WARN", msg); }

/* Mount essential filesystems */
static int mount_filesystems(void) {
    log_info("Mounting essential filesystems");
    
    /* Create mount points if they don't exist */
    mkdir("/proc", 0755);
    mkdir("/sys", 0755);
    mkdir("/dev", 0755);
    mkdir("/run", 0755);
    mkdir("/tmp", 01777);
    
    /* Mount proc */
    if (mount("proc", "/proc", "proc", MS_NODEV | MS_NOSUID | MS_NOEXEC, NULL) < 0) {
        if (errno != EBUSY) {
            log_error("Failed to mount /proc");
            return -1;
        }
    }
    
    /* Mount sysfs */
    if (mount("sysfs", "/sys", "sysfs", MS_NODEV | MS_NOSUID | MS_NOEXEC, NULL) < 0) {
        if (errno != EBUSY) {
            log_error("Failed to mount /sys");
            return -1;
        }
    }
    
    /* Mount devtmpfs */
    if (mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755") < 0) {
        if (errno != EBUSY) {
            log_error("Failed to mount /dev");
            return -1;
        }
    }
    
    /* Create /dev/pts */
    mkdir("/dev/pts", 0755);
    if (mount("devpts", "/dev/pts", "devpts", MS_NOEXEC | MS_NOSUID, "gid=5,mode=0620") < 0) {
        if (errno != EBUSY) {
            log_warn("Failed to mount /dev/pts");
        }
    }
    
    /* Mount tmpfs on /run */
    if (mount("tmpfs", "/run", "tmpfs", MS_NODEV | MS_NOSUID, "mode=0755") < 0) {
        if (errno != EBUSY) {
            log_error("Failed to mount /run");
            return -1;
        }
    }
    
    /* Mount tmpfs on /tmp */
    if (mount("tmpfs", "/tmp", "tmpfs", MS_NODEV | MS_NOSUID, "mode=1777") < 0) {
        if (errno != EBUSY) {
            log_warn("Failed to mount /tmp");
        }
    }
    
    log_info("Filesystems mounted successfully");
    return 0;
}

/* Set up hostname */
static void setup_hostname(void) {
    FILE *fp = fopen("/System/etc/hostname", "r");
    if (fp) {
        char hostname[256];
        if (fgets(hostname, sizeof(hostname), fp)) {
            hostname[strcspn(hostname, "\n")] = 0;
            if (sethostname(hostname, strlen(hostname)) == 0) {
                log_info("Hostname set");
            }
        }
        fclose(fp);
    }
}

/* Set up environment */
static void setup_environment(void) {
    setenv("PATH", "/System/usr/local/sbin:/System/usr/local/bin:/System/usr/sbin:/System/usr/bin:/System/sbin:/System/bin", 1);
    setenv("HOME", "/root", 1);
    setenv("TERM", "linux", 1);
    setenv("SHELL", "/bin/bash", 1);
}

/* Signal handlers */
static void sigchld_handler(int sig) {
    (void)sig;
    got_sigchld = 1;
}

static void sigterm_handler(int sig) {
    (void)sig;
    do_shutdown = 1;
}

static void sigint_handler(int sig) {
    (void)sig;
    do_reboot = 1;
}

static void setup_signals(void) {
    struct sigaction sa;
    
    /* SIGCHLD - child process died */
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigchld_handler;
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    sigaction(SIGCHLD, &sa, NULL);
    
    /* SIGTERM - shutdown */
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigterm_handler;
    sigaction(SIGTERM, &sa, NULL);
    
    /* SIGINT - reboot (Ctrl+Alt+Del) */
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigint_handler;
    sigaction(SIGINT, &sa, NULL);
    
    /* Ignore other signals */
    signal(SIGHUP, SIG_IGN);
    signal(SIGUSR1, SIG_IGN);
    signal(SIGUSR2, SIG_IGN);
}

/* Spawn emergency console shell */
static void spawn_emergency_console(void) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("Failed to fork emergency console");
        return;
    }
    
    if (pid == 0) {
        /* Child process */
        setsid();
        
        /* Open /dev/console for stdin, stdout, stderr */
        int fd = open("/dev/console", O_RDWR);
        if (fd < 0) {
            _exit(1);
        }
        
        dup2(fd, 0);  /* stdin */
        dup2(fd, 1);  /* stdout */
        dup2(fd, 2);  /* stderr */
        
        if (fd > 2) {
            close(fd);
        }
        
        /* Reset signals */
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        
        /* Try to exec a shell */
        char *shell_argv[] = {"/bin/sh", NULL};
        execv("/bin/sh", shell_argv);
        
        /* If /bin/sh fails, try /bin/bash */
        char *bash_argv[] = {"/bin/bash", NULL};
        execv("/bin/bash", bash_argv);
        
        /* If all fails, exit */
        fprintf(stderr, "Failed to spawn emergency console\n");
        _exit(1);
    }
    
    log_info("Emergency console spawned on /dev/console");
}

/* Spawn a service */
static pid_t spawn_service(service_t *svc) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("Failed to fork");
        return -1;
    }
    
    if (pid == 0) {
        /* Child process */
        setsid();
        
        /* Reset signals */
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        
        /* Execute service */
        execv(svc->command, svc->argv);
        
        /* If we get here, exec failed */
        fprintf(stderr, "Failed to exec %s: %s\n", svc->name, strerror(errno));
        _exit(1);
    }
    
    /* Parent process */
    svc->pid = pid;
    svc->last_spawn = time(NULL);
    svc->spawn_count++;
    
    char msg[256];
    snprintf(msg, sizeof(msg), "Started %s (PID %d)", svc->name, pid);
    log_info(msg);
    
    return pid;
}

/* Check if service should be respawned */
static int should_respawn(service_t *svc) {
    time_t now = time(NULL);
    
    /* Reset spawn count if outside respawn window */
    if (now - svc->last_spawn > RESPAWN_WINDOW) {
        svc->spawn_count = 0;
    }
    
    /* Check if we've respawned too many times */
    if (svc->spawn_count >= MAX_RESPAWN) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Service %s respawning too fast, disabling", svc->name);
        log_error(msg);
        return 0;
    }
    
    return 1;
}

/* Handle child process death */
static void handle_sigchld(service_t *services, int num_services) {
    pid_t pid;
    int status;
    
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        /* Find which service died */
        for (int i = 0; i < num_services; i++) {
            if (services[i].pid == pid) {
                char msg[256];
                
                if (WIFEXITED(status)) {
                    snprintf(msg, sizeof(msg), "Service %s exited with status %d",
                            services[i].name, WEXITSTATUS(status));
                } else if (WIFSIGNALED(status)) {
                    snprintf(msg, sizeof(msg), "Service %s killed by signal %d",
                            services[i].name, WTERMSIG(status));
                } else {
                    snprintf(msg, sizeof(msg), "Service %s died", services[i].name);
                }
                log_warn(msg);
                
                services[i].pid = 0;
                
                /* Respawn if configured */
                if (services[i].respawn && should_respawn(&services[i])) {
                    sleep(1); /* Brief delay before respawn */
                    spawn_service(&services[i]);
                }
                
                break;
            }
        }
    }
}

/* Shutdown system */
static void shutdown_system(int do_reboot_flag) {
    log_info(do_reboot_flag ? "Rebooting system..." : "Shutting down system...");
    
    /* Send SIGTERM to all processes */
    log_info("Sending SIGTERM to all processes");
    kill(-1, SIGTERM);
    sleep(2);
    
    /* Send SIGKILL to remaining processes */
    log_info("Sending SIGKILL to remaining processes");
    kill(-1, SIGKILL);
    sleep(1);
    
    /* Sync filesystems */
    log_info("Syncing filesystems");
    sync();
    
    /* Unmount filesystems */
    log_info("Unmounting filesystems");
    umount("/dev/pts");
    umount("/dev");
    umount("/proc");
    umount("/sys");
    umount("/run");
    umount("/tmp");
    
    /* Reboot or halt */
    if (do_reboot_flag) {
        reboot(RB_AUTOBOOT);
    } else {
        reboot(RB_POWER_OFF);
    }
    
    /* Should never reach here */
    while (1) pause();
}

/* Main init process */
int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    
    /* Verify we are PID 1 */
    if (getpid() != 1) {
        fprintf(stderr, "Error: init must be run as PID 1\n");
        return 1;
    }
    
    /* Print banner */
    fprintf(stderr, "\n");
    fprintf(stderr, "═══════════════════════════════════════════════════════════\n");
    fprintf(stderr, "  MochiOS Init v%s\n", INIT_VERSION);
    fprintf(stderr, "═══════════════════════════════════════════════════════════\n");
    fprintf(stderr, "\n");
    
    log_info("Starting system initialization");
    
    /* Set up signal handlers */
    setup_signals();
    
    /* Mount filesystems */
    if (mount_filesystems() < 0) {
        log_error("Failed to mount filesystems");
        return 1;
    }
    
    /* Set up hostname */
    setup_hostname();
    
    /* Set up environment */
    setup_environment();
    
    /* Check if getty exists */
    int has_getty = (access("/sbin/getty", X_OK) == 0);
    int num_services = 0;
    service_t services[4];
    
    if (has_getty) {
        /* Define services to spawn */
        char *getty1_argv[] = {"/sbin/getty", "38400", "tty1", NULL};
        char *getty2_argv[] = {"/sbin/getty", "38400", "tty2", NULL};
        char *getty3_argv[] = {"/sbin/getty", "38400", "tty3", NULL};
        char *getty4_argv[] = {"/sbin/getty", "38400", "tty4", NULL};
        
        services[0] = (service_t){"getty-tty1", "/sbin/getty", getty1_argv, 0, 1, 0, 0};
        services[1] = (service_t){"getty-tty2", "/sbin/getty", getty2_argv, 0, 1, 0, 0};
        services[2] = (service_t){"getty-tty3", "/sbin/getty", getty3_argv, 0, 1, 0, 0};
        services[3] = (service_t){"getty-tty4", "/sbin/getty", getty4_argv, 0, 1, 0, 0};
        num_services = 4;
        
        /* Spawn initial services */
        log_info("Spawning getty services");
        for (int i = 0; i < num_services; i++) {
            spawn_service(&services[i]);
        }
    } else {
        /* Getty not found, spawn emergency console */
        log_warn("Getty not found at /sbin/getty");
        log_info("Spawning emergency console on /dev/console");
        spawn_emergency_console();
    }
    
    log_info("System initialization complete");
    fprintf(stderr, "\n");
    fprintf(stderr, "═══════════════════════════════════════════════════════════\n");
    fprintf(stderr, "  MochiOS is ready\n");
    fprintf(stderr, "═══════════════════════════════════════════════════════════\n");
    fprintf(stderr, "\n");
    
    /* Main event loop */
    while (1) {
        /* Check for shutdown/reboot */
        if (do_shutdown || do_reboot) {
            shutdown_system(do_reboot);
        }
        
        /* Handle child process deaths */
        if (got_sigchld) {
            got_sigchld = 0;
            handle_sigchld(services, num_services);
        }
        
        /* Sleep briefly to avoid busy loop */
        pause();
    }
    
    return 0;
}
