/*
 * safe recursive delete, should be resitant to symlink attacks 
 * should not follow symlinks created while it is running
 * needs linux specific functions and POSIX fd bases functions
 * will not work on non linux systems 
 * code follows pattern of python shutil.rmtree
 */

// TODO: use stat calls to collect statistics of files deleted

import std.stdio;
import core.sys.posix.fcntl;
import core.sys.posix.dirent;
import core.sys.posix.sys.stat;
import core.sys.posix.unistd;
import core.stdc.string;
import std.file;
import std.conv : to;
import std.path : buildPath;
import std.string;


// some calls which are not in core.sys.posix
extern (C)  DIR *fdopendir(int fd);
extern (C)  int fstatat(int dirfd, const char *pathname, stat_t *statbuf, int flags);
extern (C)  int openat(int dirfd, const char *pathname, int flags);
extern (C)  int unlinkat(int dirfd, const char *pathname, int flags);


// not in core.sys.posix
enum AT_EMPTY_PATH = 0x1000;  /* Allow empty relative pathname */

// we need errno
extern (C) extern  int errno;

// delete path be deleting contens and deleting path itself
public void rmtree(string path) {
    stat_t orig_stat, new_stat;
    
    int r = fstatat(0 , toStringz(path), &orig_stat, AT_SYMLINK_NOFOLLOW);
    if (r) {
        stderr.writefln("ERROR: fstatat %s -> %d", path, errno);
    }

    if(S_ISDIR(orig_stat.st_mode)) {
        bool dirfd_closed = false;
        int dirfd = openat(0, toStringz(path), O_RDONLY|O_CLOEXEC);
        r = fstatat(dirfd, "", &new_stat, AT_EMPTY_PATH);
        if (r==0 && core.stdc.string.memcmp(&new_stat, &orig_stat,stat_t.sizeof)==0) {
            rmtree_fd(dirfd, path);
            close(dirfd);
            dirfd_closed = true;
            //stdout.writeln("unlink ",path);
            r=unlinkat(0, toStringz(path), AT_REMOVEDIR);
            if(r) {
                stderr.writefln("ERROR: unlinkat %s -> %d", path, errno);
            }
        }
        if (!dirfd_closed) close(dirfd);
    }
}

// internal recursiv functions, baded on file handels
void rmtree_fd(int topfd, string path) {
    auto dir = fdopendir(topfd);
    if(dir!=null) {
        dirent*[] entries;

        auto entry = readdir(dir);
        while(entry) {
            entries ~= entry;
            errno=0;
            entry = readdir(dir);
            if(entry==null && errno!=0) {
                stdout.writeln("errno:",errno);
            }
        }

        foreach(ent; entries) {
            if (ent.d_type==DT_DIR) {
                // ignore . and .. !!!!!!!
                if (core.stdc.string.strcmp(cast(const char *)&ent.d_name[0], ".") &&
                    core.stdc.string.strcmp(cast(const char *)&ent.d_name[0], "..")) 
                {
                    stat_t orig_stat, new_stat;
                   
                    int r = fstatat(topfd, cast(const char *)&ent.d_name[0], &orig_stat, AT_SYMLINK_NOFOLLOW);
                    if (r) {
                        stderr.writefln("ERROR: fstatat %d %s/%s -> %d", topfd, path, to!string(cast(const char *)&ent.d_name[0]), errno);
                        continue; 
                    }

                    if(S_ISDIR(orig_stat.st_mode)) {
                        int dirfd = openat(topfd, cast(const char *)&ent.d_name[0], O_RDONLY|O_CLOEXEC);
                        bool dirfd_closed = false;
                        r = fstatat(dirfd, "", &new_stat, AT_EMPTY_PATH);
                        if (r==0 && core.stdc.string.memcmp(&new_stat, &orig_stat,stat_t.sizeof)==0) {
                            rmtree_fd(dirfd, buildPath(path, to!string(cast(const char *)&ent.d_name[0])));
                            close(dirfd);
                            dirfd_closed = true;
                            //stdout.writeln("unlink ",path,"/",to!string(cast(const char *)&ent.d_name[0]));
                            r=unlinkat(topfd, cast(const char *)&ent.d_name[0],AT_REMOVEDIR);
                            if(r) {
                                stderr.writefln("ERROR: unlinkat %s/%s -> %d", path, to!string(cast(const char *)&ent.d_name[0]), errno);
                            }
                        } else {
                            stderr.writeln("ERROR: rmtree hit a symbolic link!");
                        }
                        if (!dirfd_closed) close(dirfd);
                    }
                } 
            } else {
                //stdout.writeln("unlink ",path,"/",to!string(cast(const char *)&ent.d_name[0]));
                int r = unlinkat(topfd, cast(const char *)&ent.d_name[0], 0);
                if(r) {
                    stderr.writefln("ERROR: unlinkat %s/%s -> %d", path, to!string(cast(const char *)&ent.d_name[0]), errno);
                }
            }
        }
        closedir(dir);  
    } else {
        stderr.writefln("ERROR: fdopendir %d -> %d", topfd, errno);
    } 
}

unittest{
    try {
        std.file.mkdirRecurse("/tmp/_wsTT/a");
    } catch(std.file.FileException) {
        // existed
    }
    try {
        std.file.mkdirRecurse("/tmp/_wsTT/b");
    } catch(std.file.FileException) {
        // existed
    }
    try {
        std.file.mkdirRecurse("/tmp/_wsTT/a/c");
    } catch(std.file.FileException) {
        // existed
    }
    try {
        std.file.write("/tmp/_wsTT/a/file","");
    } catch(std.file.FileException) {
        // existed
    }
    rmtree("/tmp/TT");
}