// 
// command line options for ws_list
//

import std.getopt;
import exit;

class Options {
	string filesystem;
	bool listgroups;
	bool listfilesystems;
	bool shortlisting;
	string user;
	bool listexpired;
	bool sortbyname;
	bool sortbycreation;
	bool sortbyremaining;
	bool sortreverted;
	bool terselisting;
	string configfile;
	bool verbose;
	bool debugflag;


	// hack auto ref allows to be called with literals (in unit tests) and with ref in real code, 
	//  but has to be template to work
	this(T)(auto ref T[] args ) {
		auto help = getopt(
			args,
			"filesystems|F", "filesystem to list workspaces from", &filesystem,
			"group|g", "enable listing of grou workspaces", &listgroups,
			"listfilesystems|l", "list available filesystems", &listfilesystems,
			"short|s", "short listing, only workspace names", &shortlisting,
			"user|u", "only show workspaces for selected user", &user,
			"expired|e", "show expired workspaces", &listexpired,
			"name|N", "sort by name", &sortbyname,
			"creation|C", "sort by creation date", &sortbycreation,
			"remaining|R", "sort by remaining time", &sortbyremaining,
			"reverted|r", "revert sort", &sortreverted,
			"terse|t", "terse listing", &terselisting,
			"config", "config file", &configfile,
			"verbose|v", "verbose listing", &verbose,
			"debug", "debugging infomation", &debugflag
		);	

		if (help.helpWanted) {
			defaultGetoptPrinter("ws_list [options] [pattern]", help.options);
			exit.exit(0);
		}
	}

}

unittest {
	// first arg is program name
	auto opttest = new Options(["unittest", "-v", "--user","tester"]);

	assert(opttest.user == "tester");
	assert(opttest.verbose == true);
}
