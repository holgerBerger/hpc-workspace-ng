import std.path : buildPath, baseName, dirName;
import std.stdio;
import std.file;
import core.stdc.time : ctime, time;
import std.string : fromStringz;
import std.conv : to;
import std.array : split;
static import core.exception;

import config;
import db;
import dbv1;


// expire workspaces expires workspace DB entries and moves the workspace to deleted directory
// deletes expired workspace in second phase
public void expire_workspaces(Config config, in string fs, in bool dryrun, in bool silent) {
    
    string[] spaces = config.spaceslist(fs);

    auto db = config.openDB();

    if(!silent) stdout.writeln("Checking DB for workspaces to be expired for ", fs);

    // search expired active workspaces in DB
    foreach(id; db.matchPattern("*", fs, "*", [], false, false)) {
        DBEntry dbentry;
        try {
            dbentry = db.readEntry(fs, id, false);
        } catch (Exception e) {
            stderr.writeln("  ERROR, skiping db entry ", id);
            continue;
        }

        auto expiration = dbentry.getExpiration;

        if (expiration<=0) {
            stderr.writeln("  ERROR, bad expiration in ", id);
            continue;            
        }

        // do we have to expire?
        if (time(cast(long *)0L) > expiration) {
            auto timestamp = to!string(time(cast(long *)0L));
            stdout.writeln("  expiring ", id, " (expired ", fromStringz(ctime(&expiration))[0..$-1], ")");
            if (!dryrun) {
                // db entry first
                db.expireEntry(fs, id, timestamp);
                // workspace second
                auto wspath = dbentry.getWSPath();
                try {
                    auto tgt = buildPath(dirName(wspath), config.deletedPath(fs), baseName(wspath) ~ "-" ~ timestamp);
                    debug{
                        stderr.writeln("   mv ", wspath, " -> ", tgt);
                    }
                    std.file.rename(wspath, tgt);
                } catch (FileException e) {
                    stderr.writeln("   ERROR, failed to move workspace: ", wspath, " (",e.msg, ")");
                }
            }
        } else {
            stdout.writeln("  keeping ",id); // TODO: add expiration time
            // TODO: reminder mails
        }
    }

    if(!silent) stdout.writeln("Checking deleted DB for workspaces to be deleted for ", fs);

    // search in DB for expired/released workspaces for those over keeptime
    foreach(id; db.matchPattern("*", fs, "*", [], true, false)) {
        DBEntry dbentry;
        try {
            dbentry = db.readEntry(fs, id, true);
        } catch (Exception e) {
            stderr.writeln("  ERROR, skiping db entry ", id);
            continue;
        }

        auto expiration = dbentry.getExpiration;  
        auto releasetime = dbentry.getReleasetime;  
        auto keeptime = config.keeptime(fs);

        // get released time from name = id
        try {
            releasetime = to!int(id.split("-")[2]);
        } catch (core.exception.ArrayIndexError) {
            stderr.writeln("  ERROR, skiping unparsable name DB entry ", id);
            continue;
        }

        auto released = dbentry.getReleasetime; // check if it was released by user
        if (released > 1_000_000_000) { // released after 2001?
            releasetime = released;
        } else {
            releasetime = 3_000_000_000;    // date in future, 2065
            stderr.writeln("  IGNORING released ",releasetime, " for ", id);
        }

        bool releasedbyuser = false;
        if (  (time(cast(long *)0L) > (expiration + keeptime*24*3600)) 
                        || (time(cast(long *)0L) > releasetime + 3600)  ) {
            if (time(cast(long *)0L) > releasetime + 3600) {
                stdout.writeln("  deleting DB entry", id, ", was released ", fromStringz(ctime(&releasetime))[1..$-1]);
            } else {
                stdout.writeln("  deleting DB entry", id, ", expired ", fromStringz(ctime(&expiration))[1..$-1]);
            }
            if(!dryrun) {
                db.deleteEntry(fs, id);
            }

            auto wspath = buildPath( dirName(dbentry.getWSPath()), config.deletedPath(fs), id);
            stdout.writeln("  deleting directory: ",wspath);
            if(!dryrun) {
                try {
                    std.file.rmdirRecurse(wspath);
                } catch (FileException e) {
                    stderr.writeln("   failed to remove: ", wspath, " (",e.msg,")");
                }
            }
        } else {
            stdout.writeln("  (keeping restorable ", id,")"); // TODO: add expiration + keeptime
        }
     
    }

}

// TODO: full test with prepared directory structure etc