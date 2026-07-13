#ifndef MIXTAR_BRIDGE_DB_H
#define MIXTAR_BRIDGE_DB_H
#pragma GCC system_header

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

typedef uint32_t db_recno_t;
typedef db_recno_t recno_t;

typedef struct {
	void *data;
	size_t size;
} DBT;

typedef struct {
	unsigned long flags;
	unsigned int cachesize;
	unsigned int psize;
	int lorder;
	size_t reclen;
	unsigned char bval;
	char *bfname;
} RECNOINFO;

#define DB_RECNO 1
#define R_CURSOR 1
#define R_FIRST 2
#define R_IAFTER 3
#define R_IBEFORE 4
#define R_LAST 5
#define R_NEXT 6
#define R_PREV 7
#define R_RECNOSYNC 8
#define R_SNAPSHOT 0x01
#define MAX_REC_NUMBER UINT32_MAX

typedef struct __mixtar_db_record {
	void *data;
	size_t size;
} __mixtar_db_record;

typedef struct __db DB;
struct __db {
	int (*close)(DB *);
	int (*del)(DB *, const DBT *, unsigned int);
	int (*fd)(DB *);
	int (*get)(DB *, const DBT *, DBT *, unsigned int);
	int (*put)(DB *, DBT *, const DBT *, unsigned int);
	int (*seq)(DB *, DBT *, DBT *, unsigned int);
	int (*sync)(DB *, unsigned int);
	__mixtar_db_record *records;
	size_t count;
	size_t capacity;
	db_recno_t last_key;
	int backing_fd;
};

static inline db_recno_t
__mixtar_db_key(const DBT *key)
{
	db_recno_t n = 0;

	if (key != NULL && key->data != NULL && key->size >= sizeof(n))
		memcpy(&n, key->data, sizeof(n));
	return n;
}

static inline int
__mixtar_db_reserve(DB *db, size_t need)
{
	__mixtar_db_record *next;
	size_t cap;

	if (need <= db->capacity)
		return 0;
	cap = db->capacity == 0 ? 16 : db->capacity;
	while (cap < need)
		cap *= 2;
	next = (__mixtar_db_record *)realloc(db->records, cap * sizeof(*next));
	if (next == NULL)
		return -1;
	memset(next + db->capacity, 0, (cap - db->capacity) * sizeof(*next));
	db->records = next;
	db->capacity = cap;
	return 0;
}

static inline int
__mixtar_db_store_at(DB *db, size_t index, const void *data, size_t size)
{
	void *copy;

	copy = NULL;
	if (size != 0) {
		copy = malloc(size);
		if (copy == NULL)
			return -1;
		memcpy(copy, data, size);
	}
	free(db->records[index].data);
	db->records[index].data = copy;
	db->records[index].size = size;
	return 0;
}

static inline int
__mixtar_db_insert_at(DB *db, size_t index, const void *data, size_t size)
{
	if (__mixtar_db_reserve(db, db->count + 1) != 0)
		return -1;
	if (index > db->count)
		index = db->count;
	memmove(db->records + index + 1, db->records + index,
	    (db->count - index) * sizeof(db->records[0]));
	memset(db->records + index, 0, sizeof(db->records[0]));
	db->count++;
	return __mixtar_db_store_at(db, index, data, size);
}

static inline int
__mixtar_db_close(DB *db)
{
	size_t i;

	if (db == NULL)
		return 0;
	for (i = 0; i < db->count; i++)
		free(db->records[i].data);
	free(db->records);
	if (db->backing_fd >= 0)
		close(db->backing_fd);
	free(db);
	return 0;
}

static inline int
__mixtar_db_del(DB *db, const DBT *key, unsigned int flags)
{
	db_recno_t n;
	size_t index;

	(void)flags;
	n = __mixtar_db_key(key);
	if (n == 0 || n > db->count)
		return 1;
	index = (size_t)n - 1;
	free(db->records[index].data);
	memmove(db->records + index, db->records + index + 1,
	    (db->count - index - 1) * sizeof(db->records[0]));
	db->count--;
	return 0;
}

static inline int
__mixtar_db_fd(DB *db)
{
	return db == NULL ? -1 : db->backing_fd;
}

static inline int
__mixtar_db_get(DB *db, const DBT *key, DBT *data, unsigned int flags)
{
	db_recno_t n;

	(void)flags;
	n = __mixtar_db_key(key);
	if (n == 0 || n > db->count)
		return 1;
	if (data != NULL) {
		data->data = db->records[n - 1].data;
		data->size = db->records[n - 1].size;
	}
	return 0;
}

static inline int
__mixtar_db_put(DB *db, DBT *key, const DBT *data, unsigned int flags)
{
	db_recno_t n;
	size_t index;

	n = __mixtar_db_key(key);
	if (flags == R_IAFTER) {
		index = n == 0 ? 0 : (size_t)n;
		return __mixtar_db_insert_at(db, index, data->data, data->size);
	}
	if (flags == R_IBEFORE) {
		index = n == 0 ? 0 : (size_t)n - 1;
		return __mixtar_db_insert_at(db, index, data->data, data->size);
	}
	if (n == 0) {
		errno = EINVAL;
		return -1;
	}
	if (__mixtar_db_reserve(db, n) != 0)
		return -1;
	while (db->count < n) {
		db->records[db->count].data = NULL;
		db->records[db->count].size = 0;
		db->count++;
	}
	return __mixtar_db_store_at(db, (size_t)n - 1, data->data, data->size);
}

static inline int
__mixtar_db_seq(DB *db, DBT *key, DBT *data, unsigned int flags)
{
	(void)flags;
	if (db->count == 0)
		return 1;
	db->last_key = (db_recno_t)db->count;
	if (key != NULL) {
		key->data = &db->last_key;
		key->size = sizeof(db->last_key);
	}
	if (data != NULL) {
		data->data = db->records[db->count - 1].data;
		data->size = db->records[db->count - 1].size;
	}
	return 0;
}

static inline int
__mixtar_db_sync(DB *db, unsigned int flags)
{
	(void)db;
	(void)flags;
	return 0;
}

static inline int
__mixtar_db_load(DB *db, const char *path)
{
	FILE *fp;
	char *line;
	size_t cap;
	ssize_t len;

	if (path == NULL)
		return 0;
	fp = fopen(path, "r");
	if (fp == NULL)
		return -1;
	line = NULL;
	cap = 0;
	while ((len = getline(&line, &cap, fp)) >= 0) {
		if (len > 0 && line[len - 1] == '\n')
			len--;
		if (__mixtar_db_insert_at(db, db->count, line, (size_t)len) != 0) {
			free(line);
			fclose(fp);
			return -1;
		}
	}
	free(line);
	fclose(fp);
	return 0;
}

static inline DB *
dbopen(const char *file, int flags, int mode, int type, const void *openinfo)
{
	DB *db;

	(void)flags;
	(void)mode;
	(void)openinfo;
	if (type != DB_RECNO) {
		errno = EINVAL;
		return NULL;
	}
	db = (DB *)calloc(1, sizeof(*db));
	if (db == NULL)
		return NULL;
	db->close = __mixtar_db_close;
	db->del = __mixtar_db_del;
	db->fd = __mixtar_db_fd;
	db->get = __mixtar_db_get;
	db->put = __mixtar_db_put;
	db->seq = __mixtar_db_seq;
	db->sync = __mixtar_db_sync;
	db->backing_fd = file == NULL ? -1 : open(file, O_RDONLY);
	if (__mixtar_db_load(db, file) != 0) {
		__mixtar_db_close(db);
		return NULL;
	}
	return db;
}

#endif /* MIXTAR_BRIDGE_DB_H */
