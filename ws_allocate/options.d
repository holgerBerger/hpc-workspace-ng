// 
// command line options for ws_list
//

import std.getopt;

class Options {
	string filesystem;
	string user;
	bool verbose;
	bool debugflag;


	this(string[] args ) {
		auto help = getopt(
			args,
			"filesystems|F", "filesystem to list workspaces from", &filesystem,
			"user|u", "only show workspaces for selected user", &user,
			"verbose|v", "verbose listing", &verbose,
			"debug", "debugging infomation", &debugflag
		);	

		if (help.helpWanted) {
			defaultGetoptPrinter("ws_list [options] [pattern]", help.options);
		}
	}

}

@("options")
unittest {
	// first arg is program name
	auto opttest = new Options(["unittest", "-v", "--user","tester"]);

	assert(opttest.user == "tester");
	assert(opttest.verbose == true);
}
