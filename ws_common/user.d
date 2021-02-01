//
// helpers to deal with usernames, groups etc
//

import std.conv;
import core.sys.posix.unistd;
import core.sys.posix.grp;
import std.stdio;

// see if we are root
bool isRoot() {
	// uid is uid of caller, not 0 for setuid(root)
	if (getuid()==0) return true;
	else return false;
}

// get current username
string getUsername() {
	return getlogin().to!string;
}

// get list of group names of current process
string[] getGrouplist() {
	string []grplist;

	// find first size and get list 
	auto size = getgroups(0, null);
	if (size == -1) return [];
	auto gids = new gid_t[size];
	auto ret = getgroups(size, &gids[0]);
	
	for(int i=0; i<ret; i++) {
		auto grpentry = getgrgid(gids[i]);
		grplist ~= grpentry.gr_name.to!string;	
	}

	return grplist;
}

// debugging helper
void dump_info() {
	stdout.writeln("username:", getUsername());
	stdout.writeln("     uid:", getuid());
	stdout.writeln("    euid:", geteuid());
	stdout.writeln("  groups:", getGrouplist());	
}
