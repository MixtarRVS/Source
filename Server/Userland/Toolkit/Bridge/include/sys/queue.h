#ifndef MIXTAR_BRIDGE_SYS_QUEUE_H
#define MIXTAR_BRIDGE_SYS_QUEUE_H

#pragma GCC system_header

#if defined(__has_include_next)
#if __has_include_next(<sys/queue.h>)
#include_next <sys/queue.h>
#endif

#ifndef LIST_INSERT_AFTER
#define LIST_INSERT_AFTER(listelm, elm, field) do { \
	if ((LIST_NEXT((elm), field) = LIST_NEXT((listelm), field)) != NULL) \
		LIST_NEXT((listelm), field)->field.le_prev = &LIST_NEXT((elm), field); \
	LIST_NEXT((listelm), field) = (elm); \
	(elm)->field.le_prev = &LIST_NEXT((listelm), field); \
} while (0)
#endif

#ifndef LIST_INSERT_BEFORE
#define LIST_INSERT_BEFORE(listelm, elm, field) do { \
	(elm)->field.le_prev = (listelm)->field.le_prev; \
	LIST_NEXT((elm), field) = (listelm); \
	*(listelm)->field.le_prev = (elm); \
	(listelm)->field.le_prev = &LIST_NEXT((elm), field); \
} while (0)
#endif
#endif

#ifndef SLIST_HEAD
#define SLIST_HEAD(name, type) \
struct name { struct type *slh_first; }
#define SLIST_HEAD_INITIALIZER(head) { NULL }
#define SLIST_ENTRY(type) \
struct { struct type *sle_next; }
#define SLIST_FIRST(head) ((head)->slh_first)
#define SLIST_END(head) NULL
#define SLIST_EMPTY(head) (SLIST_FIRST(head) == SLIST_END(head))
#define SLIST_NEXT(elm, field) ((elm)->field.sle_next)
#define SLIST_INIT(head) do { SLIST_FIRST(head) = SLIST_END(head); } while (0)
#define SLIST_INSERT_HEAD(head, elm, field) do { \
	SLIST_NEXT((elm), field) = SLIST_FIRST((head)); \
	SLIST_FIRST((head)) = (elm); \
} while (0)
#define SLIST_REMOVE_HEAD(head, field) do { \
	SLIST_FIRST((head)) = SLIST_NEXT(SLIST_FIRST((head)), field); \
} while (0)
#define SLIST_FOREACH(var, head, field) \
	for ((var) = SLIST_FIRST((head)); (var) != SLIST_END((head)); \
	    (var) = SLIST_NEXT((var), field))
#define SLIST_FOREACH_SAFE(var, head, field, tvar) \
	for ((var) = SLIST_FIRST((head)); \
	    (var) != SLIST_END((head)) && ((tvar) = SLIST_NEXT((var), field), 1); \
	    (var) = (tvar))
#endif

#ifndef LIST_HEAD
#define LIST_HEAD(name, type) \
struct name { struct type *lh_first; }
#define LIST_HEAD_INITIALIZER(head) { NULL }
#define LIST_ENTRY(type) \
struct { struct type *le_next; struct type **le_prev; }
#define LIST_FIRST(head) ((head)->lh_first)
#define LIST_EMPTY(head) (LIST_FIRST(head) == NULL)
#define LIST_NEXT(elm, field) ((elm)->field.le_next)
#define LIST_INIT(head) do { LIST_FIRST(head) = NULL; } while (0)
#define LIST_INSERT_HEAD(head, elm, field) do { \
	if ((LIST_NEXT((elm), field) = LIST_FIRST((head))) != NULL) \
		LIST_FIRST((head))->field.le_prev = &LIST_NEXT((elm), field); \
	LIST_FIRST((head)) = (elm); \
	(elm)->field.le_prev = &LIST_FIRST((head)); \
} while (0)
#define LIST_REMOVE(elm, field) do { \
	if (LIST_NEXT((elm), field) != NULL) \
		LIST_NEXT((elm), field)->field.le_prev = (elm)->field.le_prev; \
	*(elm)->field.le_prev = LIST_NEXT((elm), field); \
} while (0)
#define LIST_FOREACH(var, head, field) \
	for ((var) = LIST_FIRST((head)); (var) != NULL; \
	    (var) = LIST_NEXT((var), field))
#endif

#ifndef SIMPLEQ_HEAD
#define SIMPLEQ_HEAD(name, type) \
struct name { struct type *sqh_first; struct type **sqh_last; }
#define SIMPLEQ_HEAD_INITIALIZER(head) { NULL, &(head).sqh_first }
#define SIMPLEQ_ENTRY(type) \
struct { struct type *sqe_next; }
#define SIMPLEQ_FIRST(head) ((head)->sqh_first)
#define SIMPLEQ_NEXT(elm, field) ((elm)->field.sqe_next)
#define SIMPLEQ_EMPTY(head) (SIMPLEQ_FIRST(head) == NULL)
#define SIMPLEQ_INIT(head) do { \
	(head)->sqh_first = NULL; \
	(head)->sqh_last = &(head)->sqh_first; \
} while (0)
#define SIMPLEQ_INSERT_TAIL(head, elm, field) do { \
	SIMPLEQ_NEXT((elm), field) = NULL; \
	*(head)->sqh_last = (elm); \
	(head)->sqh_last = &SIMPLEQ_NEXT((elm), field); \
} while (0)
#define SIMPLEQ_REMOVE_HEAD(head, field) do { \
	if (((head)->sqh_first = (head)->sqh_first->field.sqe_next) == NULL) \
		(head)->sqh_last = &(head)->sqh_first; \
} while (0)
#define SIMPLEQ_FOREACH(var, head, field) \
	for ((var) = SIMPLEQ_FIRST((head)); (var) != NULL; \
	    (var) = SIMPLEQ_NEXT((var), field))
#endif

#ifndef STAILQ_HEAD
#define STAILQ_HEAD(name, type) \
struct name { struct type *stqh_first; struct type **stqh_last; }
#define STAILQ_HEAD_INITIALIZER(head) { NULL, &(head).stqh_first }
#define STAILQ_ENTRY(type) \
struct { struct type *stqe_next; }
#define STAILQ_FIRST(head) ((head)->stqh_first)
#define STAILQ_NEXT(elm, field) ((elm)->field.stqe_next)
#define STAILQ_EMPTY(head) (STAILQ_FIRST(head) == NULL)
#define STAILQ_INIT(head) do { \
	(head)->stqh_first = NULL; \
	(head)->stqh_last = &(head)->stqh_first; \
} while (0)
#define STAILQ_INSERT_TAIL(head, elm, field) do { \
	STAILQ_NEXT((elm), field) = NULL; \
	*(head)->stqh_last = (elm); \
	(head)->stqh_last = &STAILQ_NEXT((elm), field); \
} while (0)
#define STAILQ_REMOVE_HEAD(head, field) do { \
	if ((STAILQ_FIRST((head)) = STAILQ_NEXT(STAILQ_FIRST((head)), field)) == NULL) \
		(head)->stqh_last = &STAILQ_FIRST((head)); \
} while (0)
#define STAILQ_REMOVE_AFTER(head, elm, field) do { \
	if ((STAILQ_NEXT((elm), field) = STAILQ_NEXT(STAILQ_NEXT((elm), field), field)) == NULL) \
		(head)->stqh_last = &STAILQ_NEXT((elm), field); \
} while (0)
#define STAILQ_CONCAT(head1, head2) do { \
	if (!STAILQ_EMPTY((head2))) { \
		*(head1)->stqh_last = (head2)->stqh_first; \
		(head1)->stqh_last = (head2)->stqh_last; \
		STAILQ_INIT((head2)); \
	} \
} while (0)
#define STAILQ_FOREACH(var, head, field) \
	for ((var) = STAILQ_FIRST((head)); (var) != NULL; \
	    (var) = STAILQ_NEXT((var), field))
#define STAILQ_FOREACH_SAFE(var, head, field, tvar) \
	for ((var) = STAILQ_FIRST((head)); \
	    (var) != NULL && ((tvar) = STAILQ_NEXT((var), field), 1); \
	    (var) = (tvar))
#define STAILQ_SWAP(head1, head2, type) do { \
	struct type *swap_first = (head1)->stqh_first; \
	struct type **swap_last = (head1)->stqh_last; \
	(head1)->stqh_first = (head2)->stqh_first; \
	(head1)->stqh_last = (head2)->stqh_last; \
	(head2)->stqh_first = swap_first; \
	(head2)->stqh_last = swap_last; \
	if (STAILQ_EMPTY((head1))) (head1)->stqh_last = &STAILQ_FIRST((head1)); \
	if (STAILQ_EMPTY((head2))) (head2)->stqh_last = &STAILQ_FIRST((head2)); \
} while (0)
#define STAILQ_SPLIT_AFTER(head, elm, head2, field) do { \
	(head2)->stqh_first = STAILQ_NEXT((elm), field); \
	if ((head2)->stqh_first == NULL) \
		(head2)->stqh_last = &(head2)->stqh_first; \
	else \
		(head2)->stqh_last = (head)->stqh_last; \
	STAILQ_NEXT((elm), field) = NULL; \
	(head)->stqh_last = &STAILQ_NEXT((elm), field); \
} while (0)
#endif

#ifndef TAILQ_HEAD
#define TAILQ_HEAD(name, type) \
struct name { struct type *tqh_first; struct type **tqh_last; }
#define TAILQ_HEAD_INITIALIZER(head) { NULL, &(head).tqh_first }
#define TAILQ_ENTRY(type) \
struct { struct type *tqe_next; struct type **tqe_prev; }
#define TAILQ_FIRST(head) ((head)->tqh_first)
#define TAILQ_NEXT(elm, field) ((elm)->field.tqe_next)
#define TAILQ_LAST(head, headname) \
    (*(((struct headname *)((head)->tqh_last))->tqh_last))
#define TAILQ_PREV(elm, headname, field) \
    (*(((struct headname *)((elm)->field.tqe_prev))->tqh_last))
#define TAILQ_FOREACH_REVERSE(var, head, headname, field) \
    for ((var) = TAILQ_LAST((head), headname); \
        (var) != NULL; \
        (var) = TAILQ_PREV((var), headname, field))
#define TAILQ_INSERT_BEFORE(listelm, elm, field) do { \
    (elm)->field.tqe_prev = (listelm)->field.tqe_prev; \
    (elm)->field.tqe_next = (listelm); \
    *(listelm)->field.tqe_prev = (elm); \
    (listelm)->field.tqe_prev = &(elm)->field.tqe_next; \
} while (0)
#define TAILQ_INSERT_AFTER(head, listelm, elm, field) do { \
    if (((elm)->field.tqe_next = (listelm)->field.tqe_next) != NULL) \
        (elm)->field.tqe_next->field.tqe_prev = &(elm)->field.tqe_next; \
    else \
        (head)->tqh_last = &(elm)->field.tqe_next; \
    (listelm)->field.tqe_next = (elm); \
    (elm)->field.tqe_prev = &(listelm)->field.tqe_next; \
} while (0)
#define TAILQ_EMPTY(head) (TAILQ_FIRST(head) == NULL)
#define TAILQ_INIT(head) do { \
	(head)->tqh_first = NULL; \
	(head)->tqh_last = &(head)->tqh_first; \
} while (0)
#define TAILQ_INSERT_HEAD(head, elm, field) do { \
	if ((TAILQ_NEXT((elm), field) = TAILQ_FIRST((head))) != NULL) \
		TAILQ_FIRST((head))->field.tqe_prev = &TAILQ_NEXT((elm), field); \
	else \
		(head)->tqh_last = &TAILQ_NEXT((elm), field); \
	TAILQ_FIRST((head)) = (elm); \
	(elm)->field.tqe_prev = &TAILQ_FIRST((head)); \
} while (0)
#define TAILQ_INSERT_TAIL(head, elm, field) do { \
	TAILQ_NEXT((elm), field) = NULL; \
	(elm)->field.tqe_prev = (head)->tqh_last; \
	*(head)->tqh_last = (elm); \
	(head)->tqh_last = &TAILQ_NEXT((elm), field); \
} while (0)
#define TAILQ_REMOVE(head, elm, field) do { \
	if (TAILQ_NEXT((elm), field) != NULL) \
		TAILQ_NEXT((elm), field)->field.tqe_prev = (elm)->field.tqe_prev; \
	else \
		(head)->tqh_last = (elm)->field.tqe_prev; \
	*(elm)->field.tqe_prev = TAILQ_NEXT((elm), field); \
} while (0)
#define TAILQ_FOREACH(var, head, field) \
	for ((var) = TAILQ_FIRST((head)); (var) != NULL; \
	    (var) = TAILQ_NEXT((var), field))
#define TAILQ_PREV(elm, headname, field) NULL
#endif

#ifndef SIMPLEQ_REMOVE_AFTER
#define SIMPLEQ_REMOVE_AFTER(head, elm, field) do { \
	if ((((elm)->field.sqe_next) = (elm)->field.sqe_next->field.sqe_next) == NULL) \
		(head)->sqh_last = &(elm)->field.sqe_next; \
} while (0)
#endif

#ifndef SIMPLEQ_CONCAT
#define SIMPLEQ_CONCAT(head1, head2) do { \
	if (!SIMPLEQ_EMPTY((head2))) { \
		*(head1)->sqh_last = (head2)->sqh_first; \
		(head1)->sqh_last = (head2)->sqh_last; \
		SIMPLEQ_INIT((head2)); \
	} \
} while (0)
#endif

#ifndef TAILQ_FOREACH_SAFE
#define TAILQ_FOREACH_SAFE(var, head, field, tvar) \
	for ((var) = TAILQ_FIRST((head)); \
	    (var) != NULL && ((tvar) = TAILQ_NEXT((var), field), 1); \
	    (var) = (tvar))
#endif

#ifndef TAILQ_CONCAT
#define TAILQ_CONCAT(head1, head2, field) do { \
	if (!TAILQ_EMPTY((head2))) { \
		*(head1)->tqh_last = (head2)->tqh_first; \
		(head2)->tqh_first->field.tqe_prev = (head1)->tqh_last; \
		(head1)->tqh_last = (head2)->tqh_last; \
		TAILQ_INIT((head2)); \
	} \
} while (0)
#endif

#endif /* MIXTAR_BRIDGE_SYS_QUEUE_H */
