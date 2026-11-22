include 'iftrack.inc'

_bss    save_tx         dq ?
        save_rx         dq ?

        tmpdir_ptr      dq ?

        fd_ifstate      dd ?
        fd_raw_total_tx dd ?
        fd_raw_total_rx dd ?
        fd_total_tx     dd ?
        fd_total_rx     dd ?
        fd_tx_speed     dd ?
        fd_rx_speed     dd ?

        fd_if_lock      dd ?

        save_state      db ?

        full_path:      rb 128

        term            TERMIOS



_data   loop_cal        dq 0.000'098'46 ; Default: IFTRACK_FIXED_BIAS=0.09846ms

        flags           db 0

        help_text:      db 27, "[1m",'Simple interface live tracker command line utility. Version 0.1.'
                        file 'iftrack.subver'
                        db '.', 10, 27, "[0m", 'Made in assembly language with fasm2!', 10
                        db 'Usage:', 10, 10, 27, "[1m ", " %s ", 27, "[0m", "interface", 10, 10, 0

        net_path:       db '/sys/class/net'
            .search:    db '/%s/%s%s', 0
        stats_path:     db 'statistics/', 0
        oper_file:      db 'operstate', 0
        tx_file:        db 'tx_bytes', 0
        rx_file:        db 'rx_bytes'
        nullstr:        db 0, 0, 36

        bytes:          db 'B', 0
        prefix_k:       db 'k', 0, 32   ; kilo
        prefix_M:       db 'M', 0, 33   ; Mega
        prefix_G:       db 'G', 0, 31   ; Giga
        prefix_T:       db 'T', 0, 31   ; Tera
        prefix_P:       db 'P', 0, 91   ; Peta
        prefix_E:       db 'E', 0, 96   ; Exa
        prefix_i:       db 'i', 0       ; For humanized (prefix-base 1000) counters


        header:         db 27,"[3F",27,"[2K"
            .start:     db "Interface:", 27, "[1;38;5;157m %s", 27, "[0m  "
                        db "Status:", 27, "[1;%um %s  ", 27, "[0m", 27, "7", 10, 0

        info_sent:      db 27, "[2K"
            .start:     db "Sent:     " , 27, "[38;5;87m", "%7.2Lf %s%sB ", 27, "[0m"
            .cp         dw 10
                        db "[%um"
            .pp         dd "%7.2"
                        db "Lf %s%sbps", 27, "[0m", 10, 0

        info_received:  db 27, "[2K"
            .start:     db "Received: " , 27, "[38;5;221m", "%7.2Lf %s%sB ", 27, "[0m"
            .cp         dw 10
                        db "[%um"
            .pp         dd "%7.2"
                        db "Lf %s%sbps", 27, "[0m", 10, 0

        speed_fmt:      db '    Lf %sbps', 10, 0
        total_fmt:      db '%7.2Lf %sB', 10, 0
        strnl_fmt:      db '%s', 10, 0
        fp_fmt:         db '%s/%s', 0
        ifact_fmt:      db 27, "8", 27, "[%um", "↑", 27, "[%um", "↓", 27, "[0m", 27, "[3E", 0 ; ↑ ↓  🠝 🠟


        tmp_fallback:   db '/tmp', 0

        f_ifstate:      db 'ifstate', 0
        f_raw_total_tx: db 'raw_total_tx', 0
        f_raw_total_rx: db 'raw_total_rx', 0
        f_total_tx:     db 'total_tx', 0
        f_total_rx:     db 'total_rx', 0
        f_tx_speed:     db 'tx_speed', 0
        f_rx_speed:     db 'rx_speed', 0

        f_if_lock:      db '.if.lock', 0

        lock_desc       FLOCK F_WRLCK, SEEK_SET, 0, 0, 0



_code   Start entry     cmp         [rsp], dword 2
                        jne         .help

                        mov         r10, [rsp+16]
                        cmp         [r10], word '-h'
                        jne         @f
                        cmp         [r10+2], byte 0
                        je          .help
                @@      cmp         [r10], dword '--he'
                        jne         @1f
                        cmp         [r10+4], word 'lp'
                        jne         @1f
                        cmp         [r10+6], byte 0
                        je          .help

                @1      getenv("TMPDIR");
                        test        rax, rax
                        jnz         @f
                        lea         rax, [tmp_fallback]
                @@      mov         [tmpdir_ptr], rax

                        signal(SIGINT, .break);

                        sub         rsp, 256

                        call        .devcheck
                        jc          .err_open

                        snprintf(rsp, 255, net_path, [rsp+256+16], oper_file, nullstr);
                        open(rsp, O_RDONLY, .);
                        test        eax, eax
                        js          .err_open
                        mov         ebp, eax    ; ebp = operstate

                        snprintf(rsp, 255, net_path, [rsp+256+16], stats_path, tx_file);
                        open(rsp, O_RDONLY, .);
                        test        eax, eax
                        jns         @f
                        close(ebp);
                        jmp         .err_attr
                @@      mov         r12d, eax   ; r12d = tx

                        snprintf(rsp, 255, net_path, [rsp+256+16], stats_path, rx_file);
                        open(rsp, O_RDONLY, .);
                        test        eax, eax
                        jns         @f
                        close(r12d);
                        close(ebp);
                        jmp         .err_attr
                @@      mov         r13d, eax   ; r13d = rx

                        tcdrain(STDOUT_FILENO);
                        tcgetattr(STDIN_FILENO, term);
                        and         [term.lflag], not ECHO
                        tcsetattr(STDIN_FILENO, TCSADRAIN, term);

                        getenv("IFTRACK_DEBUG_ENABLE");
                        test        rax, rax
                        jz          @1f
                        cmp         [rax], word '0'
                        jne         @f
                        and         [flags], not DEBUG_ENABLE
                        jmp         @1f
                @@      cmp         [rax], word '1'
                        jne         @1f
                        or          [flags], DEBUG_ENABLE

                @1      getenv("IFTRACK_TMPFS_TRACK");
                        test        rax, rax
                        jz          @1f
                        cmp         [rax], word '0'
                        jne         @f
                        or          [flags], 1                  ; reuse 1st flag to skip tmpFS setup ¹
                        jmp         @1f
                @@      cmp         [rax], word '1'
                        jne         @1f
                        or          [flags], TMPDIR_OK

                @1      getenv("IFTRACK_PREFIX_BASE");
                        test        rax, rax
                        jz          @1f
                        mov         r9, 'hybrid'
                        mov         r10, '1000'
                        mov         r11, '1024'
                        mov         rdx, [rax]
                        mov         rcx, 0_0000_00FF_FFFF_FFFFh
                        mov         rax, 0_00FF_FFFF_FFFF_FFFFh
                        mov         r8,  0_0000_2020_2020_2020h
                        and         rcx, rdx
                        and         rax, rdx
                        cmp         rax, r9
                        jne         @f
                        or          [flags], HYBRID_SCALE
                        jmp         @1f
                @@      xor         r9, r8
                        cmp         rax, r9
                        jne         @f
                        or          [flags], HYBRID_SCALE
                        jmp         @1f
                @@      cmp         rcx, r10
                        jne         @f
                        or          [flags], HUMAN_SCALE
                        jmp         @1f
                @@      cmp         rcx, r11
                        jne         @1f
                        and         [flags], not HUMAN_SCALE

                @1      getenv("IFTRACK_FIXED_BIAS");      ; should be in ms!
                        test        rax, rax
                        jz          @1f
                        mov         rdi, rax
                        mov         rsi, rax
                        mov         ecx, 36                 ; float number + 'ms' string length should be < 36
                        xor         al, al
                        repne       scasb
                        jne         @1f
                        lea         rbx, [rdi-3]
                        cmp         [rbx], word 'ms'        ; value should be 'N.NNNNms'
                        jne         @1f
                        mov         rdi, rsp
                        xchg        rsi, rdi
                        strtold(rdi, rsi);
                        cmp         rbx, [rsp]              ; error checking
                        jne         @1f
                        mov         [rsp-4], dword 1'000
                        fidiv       dword [rsp-4]
                        fstp        [loop_cal]

                @1      emms

                        btr         dword [flags], 0        ; ¹ :: also clear flag 0 for future use
                        jnc         @f
                        test        [flags], TMPDIR_OK
                        jz          @3f

                @@      snprintf(rsp, 127, "%s/iftrack", tmpdir_ptr);
                        mkdir(rsp, 0700o);
                        snprintf(full_path, 127, "%s/%s", rsp, [rsp+256+16]);
                        mkdir(full_path, 0700o);
                        test        eax, eax
                        pushfq
                        setns       cl
                        shl         cl, 3
                        or          [flags], cl
                        popfq
                        jz          @f
                        errno();
                        cmp         [rax], dword EEXIST
                        sete        cl
                        shl         cl, 3
                        or          [flags], cl

                @@      snprintf(rsp, 127, fp_fmt, full_path, f_if_lock);
                        open(rsp, O_CREAT or O_RDWR, 0644o);
                        mov         [fd_if_lock], eax
                        test        eax, eax
                        jns         @f
                        errno();
                        mov         r14d, [rax]
                        and         [flags], not TMPDIR_OK
                        or          [flags], LOCK_U_ERR
                        jmp         @1f
                @@      fcntl(eax, F_SETLK, lock_desc);
                        test        eax, eax
                        jns         @2f
                        errno();
                        cmp         [rax], dword EACCES
                        je          @f
                        cmp         [rax], dword EAGAIN
                        je          @f
                        or          [flags], LOCK_U_ERR
                        mov         r14d, [rax]
                @@      close(fd_if_lock);
                        mov         [fd_if_lock], -1
                        and         [flags], not TMPDIR_OK
                        jmp         @1f
                @2      getpid();
                        dprintf(fd_if_lock, "%u"\n, eax);
                        fsync(fd_if_lock);

                @1      test        [flags], TMPDIR_OK
                        jnz         @3f
                        test        [flags], LOCK_U_ERR
                        jz          @f
                        dprintf(STDERR_FILENO, <27,"[1;33m","Warning:",27,"[0m","Disabling ", \
                                "'%s' statistics for this instance due to locking error: %u.", \
                                10,10,0>, full_path, r14d);
                        jmp         @3f
                @@      dprintf(STDERR_FILENO, <27,"[1;33m","Warning:",27,"[0m ", \
                                "'%s' interface already being watched by another instance.",10, \
                                "Running without updating '%s'",10,10,0>, [rsp+256+16], full_path);

                @3      read(ebp, rsp, 8);
                        mov         [rsp+rax-1], byte 0
                        mov         ecx, 31
                        mov         r11d, 33
                        mov         r10d, 32
                        cmp         rax, 3
                        cmove       ecx, r10d
                        cmp         [rsp], word 'up'
                        cmove       ecx, r10d
                        sete        [save_state]
                        mov         r9, 'unknown'
                        cmp         [rsp], r9
                        cmove       ecx, r11d
                        sete        [save_state]
                        dprintf(STDERR_FILENO, header.start, [rsp+256+16], ecx, rsp);
                        dprintf(STDERR_FILENO, <27,"[?25l",0>);

                        finit
                        read(r12d, rsp, 63);
                        mov         [rsp+rax-1], byte 0
                        strtold(rsp, NULL);
                        fst         st1
                        fistp       [save_tx]
                        call        .vformat
                        lea         rcx, [nullstr]
                        lea         r11, [prefix_i]
                        test        [flags], FLAG_LT1k
                        cmovnz      r11, rcx
                        test        [flags], HUMAN_SCALE
                        cmovnz      rcx, r11
                        dprintf(STDERR_FILENO, info_sent.start, st0, rdx, rcx);
                        read(r13d, rsp, 63);
                        mov         [rsp+rax-1], byte 0
                        strtold(rsp, NULL);
                        fst         st1
                        fistp       [save_rx]
                        call        .vformat
                        lea         rcx, [nullstr]
                        lea         r10, [prefix_i]
                        test        [flags], FLAG_LT1k
                        cmovnz      r10, rcx
                        test        [flags], HUMAN_SCALE
                        cmovnz      rcx, r10
                        dprintf(STDERR_FILENO, info_received.start, st0, rdx, rcx);

                        mov         [info_sent.cp], 1B20h
                        mov         [info_received.cp], 1B20h
                        mov         r14d, '%7.2'

                        test        [flags], TMPDIR_OK
                        jz          @f
                        chdir(full_path);
                        snprintf(rsp, 127, fp_fmt, full_path, f_ifstate);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_ifstate], eax
                        snprintf(rsp, 127, fp_fmt, full_path, f_raw_total_tx);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_raw_total_tx], eax
                        snprintf(rsp, 127, fp_fmt, full_path, f_raw_total_rx);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_raw_total_rx], eax
                        snprintf(rsp, 127, fp_fmt, full_path, f_total_tx);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_total_tx], eax
                        snprintf(rsp, 127, fp_fmt, full_path, f_total_rx);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_total_rx], eax
                        snprintf(rsp, 127, fp_fmt, full_path, f_tx_speed);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_tx_speed], eax
                        snprintf(rsp, 127, fp_fmt, full_path, f_rx_speed);
                        open(rsp, O_RDWR or O_CREAT or O_TRUNC, 0644o);
                        mov         [fd_rx_speed], eax

                @@      fldz
                        mov         [rsp], dword 1'000'000'000
                        mov         [rsp+4], dword 1'000'000

            .poll:      or          [flags], POLL_RUNNING

                        fstp        tword [rsp+16]

                        fclex
                        finit
                        fstcw       [rsp+8]
                        xor         [rsp+9], byte 1100b
                        fldcw       [rsp+8]

                        fld         tword [rsp+16]
                        fld1
                        fsubrp
                        sub         rsp, 16
                        fld         st0
                        frndint
                        fld         st0
                        fistp       qword [rsp]
                        fsubp
                        fimul       dword [rsp+16]
                        fistp       qword [rsp+8]

                        xor         [rsp+25], byte 1100b
                        fldcw       [rsp+24]

                        mov         rdi, rsp
                        mov         rsi, rsp
                        mov         eax, 35
                        syscall
                        lea         rsp, [rsp+16]
                        test        eax, eax
                        js          .endp

                        clock_gettime(CLOCK_REALTIME, rsp+240);

                        test        [flags], DEBUG_ENABLE
                        jz          @f

                        fild        qword [rsp+240]
                        fild        qword [rsp+248]
                        fidiv       dword [rsp]
                        faddp
                        fld         tword [rsp+16]
                        fimul       dword [rsp+4]
                        dprintf(STDERR_FILENO, <10,27,"[90m","Compensation: %.1Lf µs ",27,"[0K",10, \
                                "Probe timestamp: %.9Lf ",27,"[0K",27,"[0m",27,"[2F",0>, st0, st1);

                @@      lseek(ebp, 0, SEEK_SET);
                        read(ebp, rsp, 63);
                        test        rax, rax
                        jns         @f
                        call        .devcheck
                        jnc         @1f
            .endm:      emms
                        dprintf(STDERR_FILENO, <27,"[0K",10,"Device '%s' disappeared.",0>, [rsp+256+16]);
                        jmp         .endp
                @1      mov         [rsp], dword '??'
                        mov         eax, 4
                @@      mov         [rsp+rax-1], byte 0
                        mov         ecx, 31
                        mov         r11d, 33
                        mov         r10d, 32
                        cmp         rax, 3
                        cmove       ecx, r10d
                        cmp         [rsp], word 'up'
                        cmove       ecx, r10d
                        sete        [save_state]
                        je          @f
                        mov         r8, 'unknown'
                        cmp         [rsp], r8
                        cmove       ecx, r11d
                        sete        [save_state]
                @@      dprintf(STDERR_FILENO, header, [rsp+256+16], ecx, rsp);

                        test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_ifstate, 0);
                        lseek(fd_ifstate, 0, SEEK_SET);
                        dprintf(fd_ifstate, strnl_fmt, rsp);
                        fsync(fd_ifstate);

                @@      lseek(r12d, 0, SEEK_SET);
                        read(r12d, rsp, 63);
                        test        rax, rax
                        jns         @f
                        call        .devcheck
                        jc          .endm
                        jmp         @b
                @@      mov         [rsp+rax-1], byte 0

                        test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_raw_total_tx, 0);
                        lseek(fd_raw_total_tx, 0, SEEK_SET);
                        dprintf(fd_raw_total_tx, strnl_fmt, rsp);
                        fsync(fd_raw_total_tx);

                @@      strtold(rsp, NULL);
                        fld         st0
                        fild        [save_tx]
                        fsubp
                        fxch        st1
                        fistp       [save_tx]
                        mov         [rsp], dword 8
                        fimul       dword [rsp]
                        test        [flags], HYBRID_SCALE
                        jz          @f
                        or          [flags], HUMAN_SCALE
                @@      call        .vformat
                        mov         r10d, '%4.0'
                        cmovc       r10d, r14d
                        mov         [info_sent.pp], r10d
                        mov         [speed_fmt], r10d
                        mov         rbx, rdx
                        fstp        tword [rsp+32]

                        test        [flags], FLAG_LT1k
                        setnz       ch
                        shl         ch, 3
                        and         [save_state], not ST_SS_LT1k
                        or          [save_state], ch

                        test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_tx_speed, 0);
                        lseek(fd_tx_speed, 0, SEEK_SET);
                        fld         tword [rsp+32]
                        dprintf(fd_tx_speed, speed_fmt, st0, rbx);
                        fsync(fd_tx_speed);

                @@      fild        [save_tx]
                        lea         rcx, [nullstr]
                        lea         r9, [nullstr]
                        test        [flags], HYBRID_SCALE
                        jz          @f
                        and         [flags], not HUMAN_SCALE
                        jmp         @1f
                @@      lea         rcx, [prefix_i]
                        test        [flags], HUMAN_SCALE
                        cmovz       rcx, r9
                        cmp         [save_tx], 1024
                        cmovb       rcx, r9
                @1      call        .vformat
                        mov         r15, rdx
                        fld         st0
                        fstp        tword [rsp+48]
                        fld         tword [rsp+32]
                        movzx       r8d, byte [rbx+2]
                        mov         r11d, 90
                        ftst
                        fstsw       ax
                        sahf
                        cmovz       r8d, r11d
                        setnz       r10b
                        add         r10b, r10b
                        or          [save_state], r10b
                        test        [save_state], ST_NOT_DOWN
                        cmovz       r8d, r11d
                        lea         rax, [prefix_i]
                        lea         rsi, [nullstr]
                        test        [flags], HYBRID_SCALE
                        cmovnz      r9, rax
                        jnz         @f
                        test        [flags], HUMAN_SCALE
                        cmovnz      r9, rax
                @@      test        [save_state], ST_SS_LT1k
                        cmovnz      r9, rsi
                        dprintf(STDERR_FILENO, info_sent, st1, rdx, rcx, r8d, st0, rbx, r9);

                        test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_total_tx, 0);
                        lseek(fd_total_tx, 0, SEEK_SET);
                        fld         tword [rsp+48]
                        dprintf(fd_total_tx, total_fmt, st0, r15);
                        fsync(fd_total_tx);

                @@      lseek(r13d, 0, SEEK_SET);
                        read(r13d, rsp, 63);
                        test        rax, rax
                        jns         @f
                        call        .devcheck
                        jc          .endm
                        jmp         @b
                @@      mov         [rsp+rax-1], byte 0

                        test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_raw_total_rx, 0);
                        lseek(fd_raw_total_rx, 0, SEEK_SET);
                        dprintf(fd_raw_total_rx, strnl_fmt, rsp);
                        fsync(fd_raw_total_rx);

                @@      strtold(rsp, NULL);
                        fld         st0
                        fild        [save_rx]
                        fsubp
                        fxch        st1
                        fistp       [save_rx]
                        mov         [rsp], dword 8
                        fimul       dword [rsp]
                        test        [flags], HYBRID_SCALE
                        jz          @f
                        or          [flags], HUMAN_SCALE
                @@      call        .vformat
                        mov         r11d, '%4.0'
                        cmovc       r11d, r14d
                        mov         [info_received.pp], r11d
                        mov         [speed_fmt], r11d
                        mov         rbx, rdx
                        fstp        tword [rsp+32]

                        test        [flags], FLAG_LT1k
                        setnz       ch
                        shl         ch, 3
                        and         [save_state], not ST_SS_LT1k
                        or          [save_state], ch

                        test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_rx_speed, 0);
                        lseek(fd_rx_speed, 0, SEEK_SET);
                        fld         tword [rsp+32]
                        dprintf(fd_rx_speed, speed_fmt, st0, rbx);
                        fsync(fd_rx_speed);

                @@      fild        [save_rx]
                        lea         rcx, [nullstr]
                        lea         r9, [nullstr]
                        test        [flags], HYBRID_SCALE
                        jz          @f
                        and         [flags], not HUMAN_SCALE
                        jmp         @1f
                @@      lea         rcx, [prefix_i]
                        test        [flags], HUMAN_SCALE
                        cmovz       rcx, r9
                        cmp         [save_rx], 1024
                        cmovb       rcx, r9
                @1      call        .vformat
                        mov         r15, rdx
                        fld         st0
                        fstp        tword [rsp+48]
                        fld         tword [rsp+32]
                        movzx       r8d, byte [rbx+2]
                        mov         r11d, 90
                        ftst
                        fstsw       ax
                        sahf
                        cmovz       r8d, r11d
                        setnz       r10b
                        shl         r10b, 2
                        or          [save_state], r10b
                        test        [save_state], ST_NOT_DOWN
                        cmovz       r8d, r11d
                        lea         rax, [prefix_i]
                        lea         rsi, [nullstr]
                        test        [flags], HYBRID_SCALE
                        cmovnz      r9, rax
                        jnz         @f
                        test        [flags], HUMAN_SCALE
                        cmovnz      r9, rax
                @@      test        [save_state], ST_SS_LT1k
                        cmovnz      r9, rsi
                        dprintf(STDERR_FILENO, info_received, st1, rdx, rcx, r8d, st0, rbx, r9);

                        mov         edx, 92
                        mov         ecx, 91
                        mov         r11d, 90
                        test        [save_state], ST_ACT_TX
                        cmovz       edx, r11d
                        test        [save_state], ST_ACT_RX
                        cmovz       ecx, r11d
                        dprintf(STDERR_FILENO, ifact_fmt, edx, ecx);

                @@      test        [flags], TMPDIR_OK
                        jz          @f
                        ftruncate(fd_total_rx, 0);
                        lseek(fd_total_rx, 0, SEEK_SET);
                        fld         tword [rsp+48]
                        dprintf(fd_total_rx, total_fmt, st0, r15);
                        fsync(fd_total_rx);

                @@      clock_gettime(CLOCK_REALTIME, rsp+224);

                        mov         [rsp], dword 1'000'000'000
                        mov         [rsp+4], dword 1'000'000
                        fild        qword [rsp+232]
                        fidiv       dword [rsp]
                        fiadd       dword [rsp+224]
                        fild        qword [rsp+248]
                        fidiv       dword [rsp]
                        fiadd       dword [rsp+240]
                        fsubp
                        fadd        [loop_cal]

                        test        [flags], POLL_STOP
                        jz          .poll

                        emms

                        nop
                        nop

            .endp:      close(eax);
                        close(r12d);
                        close(r13d);

                        test        [flags], TMPDIR_OK
                        jz          @f

                        snprintf(rsp, 127, fp_fmt, full_path, f_ifstate);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_raw_total_tx);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_raw_total_rx);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_total_tx);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_total_rx);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_tx_speed);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_rx_speed);
                        unlink(rsp);
                        snprintf(rsp, 127, fp_fmt, full_path, f_if_lock);
                        unlink(rsp);

                        close(fd_ifstate);
                        close(fd_raw_total_tx);
                        close(fd_raw_total_rx);
                        close(fd_total_tx);
                        close(fd_total_rx);
                        close(fd_tx_speed);
                        close(fd_rx_speed);

                        close(fd_if_lock);

                        rmdir(full_path);

                        lea         rdi, [full_path+5]
                        mov         ecx, 128
                        mov         al, '/'
                        repne       scasb
                        mov         [rdi-1], byte 0
                        rmdir(full_path);

                @@      dprintf(STDERR_FILENO, <10,27,"[?25h",27,"[0J",0>);

                        or          [term.lflag], ECHO
                        tcsetattr(STDIN_FILENO, TCSAFLUSH, term);

                        exit(0);

            .vformat:   mov         eax, 1024
                        mov         r8d, 1000
                        test        [flags], HUMAN_SCALE
                        cmovnz      eax, r8d
                        push        rax

                        and         [flags], not FLAG_LT1k

                        fstp        st6
                        fild        dword [rsp]
                        fst         st5
                        fimul       dword [rsp]
                        fst         st4
                        fimul       dword [rsp]
                        fst         st3
                        fimul       dword [rsp]
                        fst         st2
                        fimul       dword [rsp]
                        fst         st1
                        fimul       dword [rsp]

                        fcomi       st6
                        ja          @f
                        lea         rdx, [prefix_E]
                        fdivr       st0, st6
                        stc
                        jmp         @1f

                @@      fincstp
                        fcomi       st5
                        ja          @f
                        lea         rdx, [prefix_P]
                        fdivr       st0, st5
                        stc
                        jmp         @1f

                @@      fincstp
                        fcomi       st4
                        ja          @f
                        lea         rdx, [prefix_T]
                        fdivr       st0, st4
                        stc
                        jmp         @1f

                @@      fincstp
                        fcomi       st3
                        ja          @f
                        lea         rdx, [prefix_G]
                        fdivr       st0, st3
                        stc
                        jmp         @1f

                @@      fincstp
                        fcomi       st2
                        ja          @f
                        lea         rdx, [prefix_M]
                        fdivr       st0, st2
                        stc
                        jmp         @1f

                @@      fincstp
                        fcomi       st1
                        ja          @f
                        lea         rdx, [prefix_k]
                        fdivr       st0, st1
                        stc
                        jmp         @1f

                @@      fincstp
                        lea         rdx, [nullstr]
                        or          [flags], FLAG_LT1k
                        clc

                @1      lea         rsp, [rsp+8]
                        ffree       st7
                        ret

            .devcheck:  sub         rsp, 280

                        pxor        xmm5, xmm5
                        movdqu      xmm4, xword [net_path]
                        movdqa      [rsp], xmm4
                        mov         rsi, [rsp+256+16+288]
                        lea         rdi, [rsp+15]
                        mov         ecx, 16

                @@      dec         ecx
                        js          @f
                        movdqu      xmm2, [rsi]
                        movdqu      [rdi], xmm2
                        pcmpeqb     xmm2, xmm5
                        pmovmskb    edx, xmm2
                        add         rsi, 16
                        add         rdi, 16
                        test        edx, edx
                        jz          @b

                        open(rsp, O_RDONLY, .);
                        test        eax, eax
                        js          @f
                        close(eax);
                        lea         rsp, [rsp+280]
                        clc
                        ret

                @@      lea         rsp, [rsp+280]
                        stc
                        ret

            .help:      dprintf(STDERR_FILENO, help_text, [rsp+8]);

                        mov         [net_path.search], byte 0
                        opendir(net_path);
                        test        rax, rax
                        jnz         @f
                        exit(7);
                @@      mov         rbx, rax
                        xor         r15d, r15d
                        xor         ebp, ebp

                @1      readdir(rbx);
                        test        rax, rax
                        jz          @f
                        cmp         [rax+DIRENT.name], '.'
                        je          @1b
                        mov         r14, rax
                        inc         r15d
                @@      test        r15d, r15d
                        jnz         @f
                        closedir(rbx);
                        exit(8);

                @@      test        rax, rax
                        jz          @1f
                        cmp         r15d, 1
                        ja          @f
                        sub         rsp, 256
                        dprintf(STDERR_FILENO, <"Available interfaces: ",27,"[38;5;229m",0>);
                @@      dprintf(STDERR_FILENO, " %s ", r14+DIRENT.name);
                        jmp         @1b

                @1      closedir(rbx);
                        dprintf(STDERR_FILENO, <27,"[0m",10,0>);
                        exit(1);

            .break:     or          [flags], POLL_STOP
                        ret

            .err_open:  errno();
                        mov         edx, [rax]
                        dprintf(STDERR_FILENO, "Error 1:%u: cannot find interface %s"\n, edx, [rsp+256+16]);
                        exit(2);

            .err_attr:  errno();
                        mov         edx, [rax]
                        dprintf(STDERR_FILENO, "Error 2:%u: a required resource could not be accessed."\n, edx);
                        exit(3);
