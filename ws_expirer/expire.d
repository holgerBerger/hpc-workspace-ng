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

public struct Clean_expire_result {
    long expired_ws;
    long kept_ws;
    long deleted_ws;
}

// expire workspace DB entries and moves the workspace to deleted directory
// deletes expired workspace in second phase
public Clean_expire_result expire_workspaces(Config config, in string fs, in bool dryrun) {
    
    Clean_expire_result result = {0, 0, 0};

    string[] spaces = config.spaceslist(fs);

    auto db = config.openDB();

    stdout.writeln("Checking DB for workspaces to be expired for ", fs);

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
            stdout.writeln(" expiring ", id, " (expired ", fromStringz(ctime(&expiration))[0..$-1], ")");
            result.expired_ws++;
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
            stdout.writeln(" keeping ",id); // TODO: add expiration time
            result.kept_ws++;
            // TODO: reminder mails
        }
    }

    stdout.writefln("  %d workspaces expired, %d kept.", result.expired_ws, result.kept_ws);

    stdout.writeln("Checking deleted DB for workspaces to be deleted for ", fs);

    // search in DB for expired/released workspaces for those over keeptime to delete them
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
        if (released > 1_000_000_000) { // released after 2001? if not ignore it
            releasetime = released;
        } else {
            releasetime = 3_000_000_000;    // date in future, 2065
            stderr.writeln("  IGNORING released ",releasetime, " for ", id);
        }

        if (  (time(cast(long *)0L) > (expiration + keeptime*24*3600)) 
                        || (time(cast(long *)0L) > releasetime + 3600)  ) {

            result.deleted_ws++;

            if (time(cast(long *)0L) > releasetime + 3600) {
                stdout.writeln(" deleting DB entry", id, ", was released ", fromStringz(ctime(&releasetime))[1..$-1]);
            } else {
                stdout.writeln(" deleting DB entry", id, ", expired ", fromStringz(ctime(&expiration))[1..$-1]);
            }
            if(!dryrun) {
                db.deleteEntry(fs, id);
            }

            auto wspath = buildPath( dirName(dbentry.getWSPath()), config.deletedPath(fs), id);
            stdout.writeln(" deleting directory: ",wspath);
            if(!dryrun) {
                try {
                    std.file.rmdirRecurse(wspath);
                } catch (FileException e) {
                    stderr.writeln("  failed to remove: ", wspath, " (",e.msg,")");
                }
            }
        } else {
            stdout.writeln(" (keeping restorable ", id,")"); // TODO: add expiration + keeptime
        }
     
    }

    stdout.writefln("  %d workspaces deleted.", result.deleted_ws);

    return result;

}

// TODO: full test with prepared directory structure etc

@("expire")
unittest {
    import dyaml;
    import yamlhelper;

	import silence;
	import options;
    import std.exception;

	auto fd1=SilenceFD(1);
	auto fd2=SilenceFD(2);

	try {
		std.file.mkdirRecurse("/tmp/_wsdb_/.removed");
	} 
	catch (std.file.FileException)
	{
		// ignore, probably already exists
	}
    try {
		std.file.mkdirRecurse("/tmp/_ws_/.removed");
	} 
	catch (std.file.FileException)
	{
		// ignore, probably already exists
	}

	auto root = Loader.fromString("filesystems:\n" ~
					"  fs:\n" ~
					"    deleted: .removed\n" ~
                    "    keeptime: 1\n" ~
                    "    spaces: [/tmp/_ws_/]\n" ~
					"    database: /tmp/_wsdb_\n").load();
	auto config = new Config(root, new Options( ["" /*,"--debug"*/ ] ), false);

	auto db = new FilesystemDBV1(config);

	// this should work
	assertNotThrown(db.createEntry("fs", "usera", "Atestws", "/tmp/_ws_/usera-Atestws", 1600515543, 1600515543, 1600515543, -3, "", "", ""));

    assert(db.matchPattern("*", "fs", "usera", [], false, false).length==1);

    auto res=expire_workspaces(config, "fs", false);
    assert(res.expired_ws==1);
    assert(res.deleted_ws==1);

    assert(db.matchPattern("*", "fs", "usera", [], true, false).length==0);
  
}