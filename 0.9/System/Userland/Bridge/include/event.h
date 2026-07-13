#ifndef MIXTAR_BRIDGE_EVENT_H
#define MIXTAR_BRIDGE_EVENT_H

#include <sys/time.h>

#define EV_READ 0x02
#define EV_WRITE 0x04
#define EV_PERSIST 0x10

struct event {
	int fd;
	short events;
	void (*callback)(int, short, void *);
	void *arg;
};

static inline void
event_init(void)
{
}

static inline void
event_set(struct event *ev, int fd, short events,
    void (*callback)(int, short, void *), void *arg)
{
	if (ev == 0)
		return;
	ev->fd = fd;
	ev->events = events;
	ev->callback = callback;
	ev->arg = arg;
}

static inline void
signal_set(struct event *ev, int sig, void (*callback)(int, short, void *),
    void *arg)
{
	event_set(ev, sig, 0, callback, arg);
}

static inline void
evtimer_set(struct event *ev, void (*callback)(int, short, void *), void *arg)
{
	event_set(ev, -1, 0, callback, arg);
}

static inline int
event_add(struct event *ev, const struct timeval *tv)
{
	(void)ev;
	(void)tv;
	return 0;
}

static inline int
signal_add(struct event *ev, const struct timeval *tv)
{
	return event_add(ev, tv);
}

static inline int
evtimer_add(struct event *ev, const struct timeval *tv)
{
	return event_add(ev, tv);
}

static inline int
event_del(struct event *ev)
{
	(void)ev;
	return 0;
}

static inline int
evtimer_del(struct event *ev)
{
	return event_del(ev);
}

static inline int
event_dispatch(void)
{
	return 0;
}

#endif
