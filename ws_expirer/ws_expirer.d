/*
 *  workspace-ng
 *
 *  ws_expirer
 *
 *  D version of workspace utility
 *  a workspace is a temporary directory created in behalf of a user with a limited lifetime.
 *
 *  (c) Holger Berger 2021, 2023
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
  *  - introduce statistics what gets deleted TODO:
  *  - remove problems with python2/3 migration and python dependencies (yaml reader)
  *  - rethink flows/make it easier to reason about
  *  
  *  - possible further directions:
  *    * parallelism 
  *    * packing of data that is expired to reduce space and inode usage
  */      
  

import std.getopt;
import std.stdio;
import std.conv;
import std.algorithm : filter, canFind;
import std.array;
import options;
import config;
import user;
import db;
import exit;
import stray;
import expire;

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
	auto config = new Config(configfile, opts, true);

    if(opts.filesystems.length>0) {
        // filter out unknown filesystems from commandline
        fslist = filter!(a => canFind(config.filesystemlist, a))(opts.filesystems).array;
    } else {
        fslist = config.filesystemlist;
    }

    debug(l2){
        stderr.writeln(" debug: [",__FUNCTION__,"] fslist: ",fslist);
    }

    if(opts.dryrun) {
        stdout.writeln("simulate cleaning - dryrun");
    } else {
        stdout.writeln("really cleaning!");
    }

    // go through filesystem and
    // stray first, move workspaces without DB entries and
    // delete deleted ones not in DB
    foreach(string fs; fslist) {
        clean_stray_directories(config, fs, opts.dryrun);
    }

    // go through database and
    // expire workspaces beyond expiration age and
    // delete expired ones which are beyond keep date
    foreach(string fs; fslist) {
        expire_workspaces(config, fs, opts.dryrun);
    }

    return 0;
}