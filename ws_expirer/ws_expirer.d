/*
 *  workspace-ng
 *
 *  ws_expirer
 *
 *  D version of workspace utility
 *  a workspace is a temporary directory created in behalf of a user with a limited lifetime.
 *
 *  (c) Holger Berger 2021
 * 
 *  workspace-ng is based on workspace by Holger Berger, Thomas Beisel and Martin Hecht
 *
 *  workspace-ng is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  workspace-ng is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with workspace-ng  If not, see <http://www.gnu.org/licenses/>.
 *
 */

 /* Rational for rewrite
  *  - introduce DB abstraction
  *  - delete fast and secure with low number of systemcalls
  *  - lower number of stat()/lstat() calls 
  *  - introduce statistics what gets deleted
  *  - remove problems with python2/3 migration and python dependencies (yaml reader)
  *  - rethink flows/make it easier to reason about
  *  
  *  - possible further directions:
  *    * parallelism 
  *    * packing of data that is expired to reduce space and inode usage
  */      
  

import std.getopt;
import std.stdio;
import std.algorithm;
import std.conv;
import std.file;
import std.array;
import std.path : buildPath, baseName;
import options;
import config;
import user;
import db;
import exit;

Options opts;
string[] fslist;

int main(string[] args)
{
	try {
		opts = new Options(args);
	}
	catch (std.getopt.GetOptException e) {
		stdout.writeln("error: ", e.msg);
		return -1;
	}
	catch (std.conv.ConvException e) {
		stdout.writeln("error: ", e.msg);
		return -1;
	}
	catch (exit.ExitException) {
		return 0;
	}


    // check if setuid - probably a bad idea
    if (!notSetuid) {
        stderr.writeln("error: ws_expirer should be not setuid.");
        return -1;
    }


	// read config 
	//   user can change this if no setuid installation OR if root
	string configfile = "/etc/ws.conf";
	if (opts.configfile!="") {
		if (isRoot() || notSetuid()) {
			configfile = opts.configfile;	
		} else {
			stderr.writeln("warning: ignored config file options!");
		}
	}
	auto config = new Config(configfile, opts);

    if(opts.filesystems.length>0) {
        fslist = opts.filesystems;
        // FIXME: verify that fs exists in config
    } else {
        fslist = config.filesystemlist;
    }

    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] fslist: ",fslist);
    }

    if(opts.dryrun) {
        stdout.writeln("simulate cleaning - dryrun");
    } else {
        stdout.writeln("really cleanin...");
    }

    foreach(string fs; fslist) {
        clean_stray_directories(config, fs, opts.dryrun);
    }

    return 0;
}


void clean_stray_directories(Config config, const string fs, const bool dryrun) {
    
    long valid=0;
    long invalid=0;

    string[] spaces = config.spaceslist(fs);
    string[] dirs;      // list of all directories in all spaces of 'fs'

    stdout.writeln("PHASE: stray directory removel for ", fs);
    stdout.writeln("workspaces first...");

    // find directories first, check DB entries later, to prevent data race with workspaces
    // getting created while this is running
    foreach(string space; spaces) {
            dirs ~= std.file.dirEntries(space, "*-*", SpanMode.shallow).filter!(a => a.isDir).map!(a => a.name).array;
            // NOTE: *-* for compatibility with old expirer
    }
    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] dirs: ",dirs);
    }


    // get all workspace pathes from DB
    auto db = config.openDB();
    auto wsIDs = db.matchPattern("*", fs, "*", null, false, false );
    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] wsIDs: ", wsIDs);
    }
    string[] workspacesInDB;
    workspacesInDB.reserve(wsIDs.length);
    foreach(wsID wsid; wsIDs) {
        // this is very defensiv, reading should not fail
        auto e = db.readEntry(fs, wsid.user, wsid.id, false);
        assert(e !is null);
        if (e!is null) workspacesInDB ~= e.getWSPath();
    }
    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] workspacesInDB: ", workspacesInDB);
    }

    // compare filesystem with DB
    foreach(string dir; dirs) {
        if(!canFind(workspacesInDB, dir)) {
            stdout.writeln("  stray workspace", dir);
            // TODO: move to deleted
            invalid++;
        } else {
            valid++;
        }
    }

    stdout.writefln("%d valid, %d invalid directories found.", valid, invalid);

    stdout.writeln("deleted workspaces second...");
    valid=0;
    invalid=0;
    dirs.length=0;
    // directory entries first
    foreach(string space; spaces) {
            dirs ~= std.file.dirEntries(buildPath(space,config.deletedPath(fs)), "*-*", SpanMode.shallow).filter!(a => a.isDir).map!(a => a.name).array;
            // NOTE: *-* for compatibility with old expirer
    }
    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] dirs: ",dirs);
    }

    // get all workspace names from DB, this contains the timestamp
    wsIDs = db.matchPattern("*", fs, "*", null, true, false );
    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] wsIDs: ", wsIDs);
    }
    workspacesInDB.length=0;
    foreach(wsID wsid; wsIDs) {
        workspacesInDB ~= (wsid.user ~ "-" ~ wsid.id);
    }
    debug{
        stderr.writeln(" debug: [",__FUNCTION__,"] workspacesInDB: ", workspacesInDB);
    }

    // compare filesystem with DB
    foreach(string dir; dirs) {
        if(!canFind(workspacesInDB, baseName(dir))) {
            stdout.writeln("  stray workspace", dir);
            // TODO: move to deleted
            invalid++;
        } else {
            valid++;
        }
    }
    stdout.writefln("%d valid, %d invalid directories found.", valid, invalid);
}