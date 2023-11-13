import std.stdio;
import std.file;
import std.path : buildPath, baseName;
import std.algorithm : filter, canFind, map;
import std.array;
import db;
import config;

public struct Clean_stray_result {
    long valid_ws;
    long invalid_ws;
    long valid_deleted;
    long invalid_deleted;
}

// clean_stray_directtories
//  finds directories that are not in DB and removes them,
//  returns numbers of valid and invalid directories
//  silent==true to avoid output for unit tests
public Clean_stray_result clean_stray_directories(Config config, in string fs, in bool dryrun, in bool silent) {
    
    Clean_stray_result result = {0, 0, 0, 0};

    string[] spaces = config.spaceslist(fs);
    string[] dirs;      // list of all directories in all spaces of 'fs'

    if(!silent) {
        stdout.writeln("PHASE: stray directory removel for ", fs);
        stdout.writeln("workspaces first...");
    }

    // find directories first, check DB entries later, to prevent data race with workspaces
    // getting created while this is running
    foreach(string space; spaces) {
            dirs ~= std.file.dirEntries(space, "*-*", SpanMode.shallow).filter!(a => a.isDir).map!(a => a.name).array;
            // NOTE: *-* for compatibility with old expirer
    }

    // get all workspace pathes from DB
    auto db = config.openDB();
    auto wsIDs = db.matchPattern("*", fs, "*", null, false, false );
    string[] workspacesInDB;
    workspacesInDB.reserve(wsIDs.length);
    foreach(WsId wsid; wsIDs) {
        // this can throw in cases of bad config
        workspacesInDB ~= db.readEntry(fs, wsid.user, wsid.id, false).getWSPath();
    }

    debug(l2){
        stderr.writeln(" debug: [",__FUNCTION__,"] dirs: ",dirs);
        stderr.writeln(" debug: [",__FUNCTION__,"] wsIDs: ", wsIDs);
        stderr.writeln(" debug: [",__FUNCTION__,"] workspacesInDB: ", workspacesInDB);
    }

    // compare filesystem with DB
    foreach(string dir; dirs) {
        if(!canFind(workspacesInDB, dir)) {
            if(!silent) stdout.writeln("  stray workspace ", dir);
            // TODO: move to deleted
            result.invalid_ws++;
        } else {
            result.valid_ws++;
        }
    }

    if(!silent) {
        stdout.writefln("%d valid, %d invalid directories found.", result.valid_ws, result.invalid_ws);
        
        stdout.writeln("deleted workspaces second...");
    }

    dirs.length=0;
    // directory entries first
    foreach(string space; spaces) {
            dirs ~= std.file.dirEntries(buildPath(space,config.deletedPath(fs)), "*-*", 
                        SpanMode.shallow).filter!(a => a.isDir).map!(a => a.name).array;
            // NOTE: *-* for compatibility with old expirer
    }

    // get all workspace names from DB, this contains the timestamp
    wsIDs = db.matchPattern("*", fs, "*", null, true, false );
    workspacesInDB.length=0;
    foreach(WsId wsid; wsIDs) {
        workspacesInDB ~= (wsid.user ~ "-" ~ wsid.id);
    }
    debug(l2){
        stderr.writeln(" debug: [",__FUNCTION__,"] dirs: ",dirs);
        stderr.writeln(" debug: [",__FUNCTION__,"] wsIDs: ", wsIDs);
        stderr.writeln(" debug: [",__FUNCTION__,"] workspacesInDB: ", workspacesInDB);
    }

    // compare filesystem with DB
    foreach(string dir; dirs) {
        if(!canFind(workspacesInDB, baseName(dir))) {
            if(!silent) stdout.writeln("  stray workspace ", dir);
            // TODO: move to deleted
            result.invalid_deleted++;
        } else {
            result.valid_deleted++;
        }
    }
    if(!silent) {
        stdout.writefln("%d valid, %d invalid directories found.", result.valid_deleted, result.invalid_deleted);
    }

    return result;

}

unittest{
    import dyaml;
    import options;
    import std.exception;

    try {
		std.file.mkdir("/tmp/straywsdb");
        
	} 
	catch (std.file.FileException){}

    try {
        std.file.mkdir("/tmp/strayws");
    }
    catch (std.file.FileException){}

    try {
        std.file.mkdir("/tmp/strayws/user-id");
    }
    catch (std.file.FileException){}

	auto root = Loader.fromString("filesystems:\n" ~
					"  fs:\n" ~
					"    database: /tmp/straywsdb\n" ~
                    "    spaces: [/tmp/strayws]\n").load();
	auto config = new Config(root, new Options( ["" /*,"--debug"*/ ] ));

    Clean_stray_result result;
    assertThrown(clean_stray_directories(config, "wrongfs", true, true));
    assertNotThrown(result=clean_stray_directories(config, "fs", true, true));
    assert(result.invalid_ws==1);
}