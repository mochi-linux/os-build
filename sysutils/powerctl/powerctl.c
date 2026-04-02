/*
 * powerctl - Power control utility for MochiOS
 * 
 * Provides poweroff, reboot, and halt commands with optional force mode
 * using sysrq triggers for emergency situations.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/reboot.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>

#define VERSION "1.0"

typedef enum {
    ACTION_POWEROFF,
    ACTION_REBOOT,
    ACTION_HALT
} action_t;

static void show_usage(const char *progname) {
    printf("Usage: %s [OPTIONS]\n", progname);
    printf("\n");
    printf("Power control utility for MochiOS\n");
    printf("\n");
    printf("Options:\n");
    printf("  -f, --force       Force immediate action using sysrq trigger\n");
    printf("  -h, --help        Show this help message\n");
    printf("  -v, --version     Show version information\n");
    printf("\n");
    printf("Commands (based on program name):\n");
    printf("  poweroff          Power off the system\n");
    printf("  reboot            Reboot the system\n");
    printf("  halt              Halt the system\n");
    printf("\n");
    printf("Examples:\n");
    printf("  poweroff          # Graceful shutdown\n");
    printf("  reboot --force    # Immediate reboot via sysrq\n");
    printf("  halt              # Halt system\n");
    printf("\n");
}

static void show_version(void) {
    printf("powerctl version %s\n", VERSION);
    printf("MochiOS power control utility\n");
}

static int sysrq_trigger(char trigger) {
    int fd = open("/proc/sysrq-trigger", O_WRONLY);
    if (fd < 0) {
        fprintf(stderr, "Error: Cannot open /proc/sysrq-trigger: %s\n", strerror(errno));
        fprintf(stderr, "Make sure you have root privileges and sysrq is enabled.\n");
        return -1;
    }
    
    if (write(fd, &trigger, 1) != 1) {
        fprintf(stderr, "Error: Failed to write to sysrq-trigger: %s\n", strerror(errno));
        close(fd);
        return -1;
    }
    
    close(fd);
    return 0;
}

static int do_force_action(action_t action) {
    char trigger;
    const char *action_name;
    
    switch (action) {
        case ACTION_POWEROFF:
            trigger = 'o';  /* sysrq-o: power off */
            action_name = "power off";
            break;
        case ACTION_REBOOT:
            trigger = 'b';  /* sysrq-b: reboot */
            action_name = "reboot";
            break;
        case ACTION_HALT:
            trigger = 'b';  /* sysrq-b: reboot (halt uses same) */
            action_name = "halt";
            break;
        default:
            fprintf(stderr, "Error: Invalid action\n");
            return 1;
    }
    
    printf("Force %s via sysrq trigger...\n", action_name);
    
    /* Sync filesystems first */
    printf("Syncing filesystems...\n");
    if (sysrq_trigger('s') < 0) {
        fprintf(stderr, "Warning: Failed to sync filesystems\n");
    }
    sleep(1);
    
    /* Remount read-only */
    printf("Remounting filesystems read-only...\n");
    if (sysrq_trigger('u') < 0) {
        fprintf(stderr, "Warning: Failed to remount read-only\n");
    }
    sleep(1);
    
    /* Execute action */
    printf("Executing %s...\n", action_name);
    if (sysrq_trigger(trigger) < 0) {
        return 1;
    }
    
    /* Should not reach here */
    sleep(5);
    fprintf(stderr, "Error: System did not %s\n", action_name);
    return 1;
}

static int do_graceful_action(action_t action) {
    int cmd;
    const char *action_name;
    
    switch (action) {
        case ACTION_POWEROFF:
            cmd = RB_POWER_OFF;
            action_name = "power off";
            break;
        case ACTION_REBOOT:
            cmd = RB_AUTOBOOT;
            action_name = "reboot";
            break;
        case ACTION_HALT:
            cmd = RB_HALT_SYSTEM;
            action_name = "halt";
            break;
        default:
            fprintf(stderr, "Error: Invalid action\n");
            return 1;
    }
    
    printf("Sending %s signal to init...\n", action_name);
    
    /* Send signal to init (PID 1) */
    if (action == ACTION_REBOOT) {
        kill(1, SIGINT);  /* Init handles SIGINT as reboot */
    } else {
        kill(1, SIGTERM); /* Init handles SIGTERM as shutdown */
    }
    
    /* Wait a moment for init to handle it */
    sleep(2);
    
    /* If init didn't handle it, use reboot syscall directly */
    printf("Executing %s...\n", action_name);
    sync();
    
    if (reboot(cmd) < 0) {
        fprintf(stderr, "Error: Failed to %s: %s\n", action_name, strerror(errno));
        return 1;
    }
    
    /* Should not reach here */
    sleep(5);
    fprintf(stderr, "Error: System did not %s\n", action_name);
    return 1;
}

int main(int argc, char *argv[]) {
    action_t action;
    int force = 0;
    const char *progname = argv[0];
    
    /* Determine action from program name */
    const char *basename = strrchr(progname, '/');
    if (basename) {
        basename++;
    } else {
        basename = progname;
    }
    
    if (strcmp(basename, "poweroff") == 0) {
        action = ACTION_POWEROFF;
    } else if (strcmp(basename, "reboot") == 0) {
        action = ACTION_REBOOT;
    } else if (strcmp(basename, "halt") == 0) {
        action = ACTION_HALT;
    } else {
        fprintf(stderr, "Error: Unknown command '%s'\n", basename);
        fprintf(stderr, "This program should be called as 'poweroff', 'reboot', or 'halt'\n");
        return 1;
    }
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--force") == 0) {
            force = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            show_usage(basename);
            return 0;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            show_version();
            return 0;
        } else {
            fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
            fprintf(stderr, "Try '%s --help' for more information.\n", basename);
            return 1;
        }
    }
    
    /* Check if running as root */
    if (geteuid() != 0) {
        fprintf(stderr, "Error: This command must be run as root\n");
        return 1;
    }
    
    /* Execute action */
    if (force) {
        return do_force_action(action);
    } else {
        return do_graceful_action(action);
    }
}
