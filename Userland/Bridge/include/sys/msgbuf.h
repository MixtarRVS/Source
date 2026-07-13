#ifndef MIXTAR_BRIDGE_SYS_MSGBUF_H
#define MIXTAR_BRIDGE_SYS_MSGBUF_H

#define MSG_MAGIC 0x063062

struct msgbuf {
	long msg_magic;
	long msg_bufx;
	long msg_bufr;
	long msg_bufs;
	char msg_bufc[];
};

#endif
