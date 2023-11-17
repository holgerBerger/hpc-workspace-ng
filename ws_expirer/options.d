// 
// command line options for ws_expirer
//

import std.stdio;
import std.getopt;
import exit;

class Options {
	string[] filesystems;
    string configfile;
	bool cleaner;
    bool dryrun=false;
    bool verbose;
    bool syslog;	// TODO: needs implementation
	bool debugflag;


	// hack auto ref allows to be called with literals (in unit tests) and with ref in real code, 
	//  but has to be template to work
	this(T)(auto ref T[] args ) {
        arraySep = ",";
		auto help = getopt(
			args,
			std.getopt.config.bundling, std.getopt.config.caseSensitive,
			"filesystem|F", "filesystems to clean workspaces from (comma separated list)", &filesystems,
            "configfile", "configuration file (default: /etc/ws.conf", &configfile, 
            "cleaner", "enable cleaner, default is dry-run", &cleaner,
            "dryrun|dry-run", "dryrun,do nothing (default)", &dryrun,
            "syslog", "log to syslog instead of stdout/err", &syslog,
			"verbose|v", "verbose listing", &verbose,
			"debug", "debugging infomation", &debugflag
		);	

		if (help.helpWanted) {
			defaultGetoptPrinter("usage: ws_expirer [options]\n\noptions:", help.options);
			exit.exit(0);
		}

        if(cleaner && dryrun) {
            stdout.writeln("error: dryrun and cleaner can not be given both. Exiting.");
            exit.exit(-1);
        }

        if (cleaner) dryrun = false; else dryrun = true;

	}

}

unittest {
	// first arg is program name
	auto opttest = new Options(["unittest", "-v", "--filesystem","test1,test2"]);

	assert(opttest.filesystems[0] == "test1");
    assert(opttest.filesystems[1] == "test2");
	assert(opttest.verbose == true);
    assert(opttest.dryrun == true);
}