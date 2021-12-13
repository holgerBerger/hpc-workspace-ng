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

    if(opts.filesystems) {
        fslist = opts.filesystems;
        // FIXME: verify that fs exists in config
    } else {
        fslist = config.filesystemlist;
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
    
    string[] spaces = config.spaceslist(fs);
    string[] dirs;

    foreach(string space; spaces) {
            dirs ~= std.file.dirEntries(space, "*", SpanMode.shallow).filter!(a => a.isDir).map!(a => a.name).array;
    }
    stderr.writeln(dirs);
}