format ELF64

include 'fastcall.inc'
include 'stdio.inc'

struct  DIRENT
        .ino    dq ?
        .off    dq ?
        .reclen dw ?
        .type   db ?
        .name   rb 256
end struct&

struct  TERMIOS
        .iflag              rd 1
        .oflag              rd 1
        .cflag              rd 1
        .lflag              rd 1
        .line               rd 1
        .cc                 rb 32
        .ispeed             rd 1
        .ospeed             rd 1
end struct

struct TIMESPEC
        .sec    dq ?
        .nsec   dq ?
end struct&

struct FLOCK tp:?, wh:?, st:?, ln:?, id:?
        .type   dw tp
        .whence dw wh
                dd ?
        .start  dq st
        .len    dq ln
        .pid    dd id
                dd ?
end struct

POLL_STOP    = 1    ; signal to stop execution
POLL_RUNNING = 2    ; in the poll loop
FLAG_LT1k    = 4    ; data below 1k
TMPDIR_OK    = 8    ; path at /tmp is exclusive and available
LOCK_U_ERR   = 16   ; lockfile unhandled error state
DEBUG_ENABLE = 32   ; enable compensation/timestamp debug string
HUMAN_SCALE  = 64   ; enable human base 1000 statistics prefix on counters. Default: base 1024 (binary mode)
HYBRID_SCALE = 128  ; when set, data amount is 1024 based, and speed is 1000 based prefix (like Netspeed widget)

ST_NOT_DOWN  = 1    ; interface up or unknown
ST_ACT_TX    = 2    ; TX activity
ST_ACT_RX    = 4    ; RX activity
ST_SS_LT1k   = 8    ; Sampled speed below 1kbps (or 1kibps)

