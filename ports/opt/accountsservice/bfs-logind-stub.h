#ifndef BFS_LOGIND_STUB_H
#define BFS_LOGIND_STUB_H

#include <errno.h>
#include <sys/types.h>

/*
 * BFSOS uses OpenRC and ConsoleKit instead of logind.  Accountsservice only
 * uses libsystemd for optional session enumeration and activation; provide
 * matching no-op entry points so user/account management still builds and
 * runs without libsystemd.
 */
typedef struct sd_login_monitor sd_login_monitor;

static inline int
sd_session_get_class (const char *session, char **class)
{
        (void) session;
        (void) class;
        return -ENOSYS;
}

static inline int
sd_session_get_seat (const char *session, char **seat)
{
        (void) session;
        (void) seat;
        return -ENOSYS;
}

static inline int
sd_seat_can_multi_session (const char *seat)
{
        (void) seat;
        return -ENOSYS;
}

static inline int
sd_session_get_type (const char *session, char **type)
{
        (void) session;
        (void) type;
        return -ENOSYS;
}

static inline int
sd_session_get_state (const char *session, char **state)
{
        (void) session;
        (void) state;
        return -ENOSYS;
}

static inline int
sd_uid_get_sessions (uid_t uid, int require_active, char ***sessions)
{
        (void) uid;
        (void) require_active;
        (void) sessions;
        return -ENOSYS;
}

static inline int
sd_session_get_uid (const char *session, uid_t *uid)
{
        (void) session;
        (void) uid;
        return -ENOSYS;
}

static inline int
sd_session_get_display (const char *session, char **display)
{
        (void) session;
        (void) display;
        return -ENOSYS;
}

static inline int
sd_get_sessions (char ***sessions)
{
        (void) sessions;
        return -ENOSYS;
}

static inline int
sd_login_monitor_new (const char *category, sd_login_monitor **ret)
{
        (void) category;
        if (ret != NULL)
                *ret = NULL;
        return -ENOSYS;
}

static inline int
sd_login_monitor_get_fd (sd_login_monitor *monitor)
{
        (void) monitor;
        return -1;
}

static inline int
sd_login_monitor_flush (sd_login_monitor *monitor)
{
        (void) monitor;
        return -ENOSYS;
}

static inline sd_login_monitor *
sd_login_monitor_unref (sd_login_monitor *monitor)
{
        return monitor;
}

#endif
