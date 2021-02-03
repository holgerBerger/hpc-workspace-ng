/*
 *  workspace-ng
 *
 *  ws_list
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


import std.getopt;
import std.stdio;
import std.algorithm;
import options;
import config;
import user;
import db;

Options opts;

void main(string[] args)
{
	opts = new Options(args);

	if (opts.verbose) {
		dump_info();
	}

	// read config FIXME user can change this is no setuid installation OR if root
	string configfile = "/etc/ws.conf";
	if (opts.configfile!="") {
		if (isRoot() || notSetuid()) {
			configfile = opts.configfile;	
		} else {
			stderr.writeln("warning: ignored config file options!");
		}
	}
	auto config =  new Config(configfile, opts);

	// root and admins can choose usernames
	string username;
	if (isRoot() && opts.user!="") {
		username = opts.user;	
	} else {
		username = getUsername();
	}

	// list of groups of this process
	auto grouplist = getGrouplist();


	// list of fileystems or list of workspaces
	if (opts.listfilesystems) {
		stdout.writeln("available filesystems (sorted according to priority):");
		foreach(fs; config.validFilesystems(username,grouplist)) {
			stdout.writeln(fs);
		}
	} else {
		auto db = config.OpenDB();
		string pattern;
		bool sort = opts.sortbyname || opts.sortbycreation || opts.sortbyremaining;
		DBEntry[] entrylist;

		// add pattern from commandline
		if (args.length>1) {
			pattern ~= args[$-1];
		} else {
			pattern ~= "*";
		}
			
		// where to list from?
		string[] fslist;
		string[] validfs = config.validFilesystems(username,grouplist);
		if (opts.filesystem != "") {
			if (canFind(validfs, opts.filesystem)) {
				fslist = [opts.filesystem];
			} else {
				stderr.writeln("error: invalid filesystem given.");
			}
		} else {
			fslist = config.validFilesystems(username,grouplist);
		}

		// iterate over filesystems
		foreach(fs; fslist) {
			try {
				foreach(id; db.matchPattern(pattern, fs, username, grouplist, opts.listexpired, opts.listgroups)) {
					auto entry = db.readEntry(fs, username, id, opts.listexpired);
					// if no sorting, print
					if (!sort)
						entry.print(opts.verbose, opts.terselisting);
					else		
						entrylist ~= entry;
				}
			} 
			catch (std.file.FileException e) {
				if(opts.debugflag) stdout.writeln("access error fs",fs);
			}
		}

		if(sort) {
			if(opts.sortbyremaining) std.algorithm.sort!( (x, y) => x.getRemaining > y.getRemaining )(entrylist);
			if(opts.sortbycreation)  std.algorithm.sort!( (x, y) => x.getCreation > y.getCreation )(entrylist);
			if(opts.sortbyname) 	 std.algorithm.sort!( (x, y) => x.getId > y.getId )(entrylist);

			if(opts.sortreverted) entrylist.reverse;

			foreach(entry; entrylist) {
				entry.print(opts.verbose, opts.terselisting);
			}
		}
		
	}
}

version(unittest)
unittest {
}
